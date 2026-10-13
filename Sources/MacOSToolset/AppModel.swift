import AppKit
import Combine
import UserNotifications
import ToolsetCore

public enum ParentAction: String { case terminate, force, restart }

@MainActor
final class AppModel: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var preferences = Preferences()
    @Published var incidents: [Incident] = []
    @Published var totalProcesses = 0
    @Published var zombieCount = 0
    @Published var lastCheck: Date?
    @Published var isChecking = false
    @Published var monitorError: String?
    @Published var storageError: String?
    @Published var sleepError: String?
    @Published var notice: String?
    @Published var actualSleep: SleepMode = .off
    @Published var loginStatus = "Проверяется"
    @Published var notificationsStatus = "Проверяется"
    @Published var selectedIncident: UUID?
    @Published var busyAction: UUID?
    var showDashboard: (() -> Void)?
    let closedLid = ClosedLidService()
    private var closedLidObservation: AnyCancellable?
    private let power = SleepState(backend: PowerAssertions())
    private var engine = IncidentEngine()
    private var store: DiagnosticWorker?
    private var timer: Timer?
    private var observationGate = ObservationGate()
    private var maintenanceTimer: Timer?
    private var generation = 0
    private var observers: [NSObjectProtocol] = []
    private let prefsKey = "toolset.preferences.v1"
    private let defaults = UserDefaults.standard
    private var shutdownRequested = false

    override init() {
        super.init()
        if let data = defaults.data(forKey: prefsKey) {
            do { preferences = try JSONDecoder().decode(Preferences.self, from: data) }
            catch { storageError = "Настройки повреждены: \(error.localizedDescription). Использованы значения по умолчанию." }
        }
        preferences.validate()
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        store = DiagnosticWorker(directory: base.appendingPathComponent("MacOSToolset", isDirectory: true))
        engine = IncidentEngine(threshold: preferences.threshold, history: incidents)
    }
    func start() {
        UNUserNotificationCenter.current().delegate = self
        closedLidObservation = closedLid.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        closedLid.start(preferredEnabled: preferences.closedLidEnabled)
        setSleepMode(preferences.sleepMode)
        if !preferences.onboardingComplete {
            preferences.onboardingComplete = true; savePreferences()
            requestNotificationPermission()
            setLoginEnabled(true)
        }
        refreshPermissions()
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resetMonitoring() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resetMonitoring(); self?.checkNow() }
        })
        Task {
            do {
                if let store { incidents = try await store.start() }
                engine = IncidentEngine(threshold: preferences.threshold, history: incidents)
            } catch { storageError = "Диагностика: \(error.localizedDescription)" }
            schedule(); checkNow()
        }
        maintenanceTimer = Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let store = self.store else { return }
                do { try await store.prune() }
                catch { self.storageError = "Очистка диагностики: \(error.localizedDescription)" }
            }
        }
    }
    func setClosedLidEnabled(_ enabled: Bool) {
        preferences.closedLidEnabled = enabled; savePreferences()
        Task { await closedLid.setEnabled(enabled) }
    }
    func removeClosedLidHelper() {
        Task {
            do { try await closedLid.removeHelper(); preferences.closedLidEnabled = false; savePreferences() }
            catch { notice = error.localizedDescription }
        }
    }
    func stop() {
        shutdownRequested = true
        timer?.invalidate(); maintenanceTimer?.invalidate()
        generation += 1
        try? power.set(.off)
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
    private func savePreferences() {
        do { defaults.set(try JSONEncoder().encode(preferences), forKey: prefsKey) }
        catch { storageError = "Не удалось сохранить настройки: \(error.localizedDescription)" }
    }
    func setMonitorEnabled(_ enabled: Bool) {
        preferences.monitorEnabled = enabled; savePreferences(); resetMonitoring(); schedule()
        if enabled { checkNow() }
    }
    func updateMonitoring(intervalMinutes: Double, threshold: Int) {
        preferences.intervalSeconds = intervalMinutes * 60
        preferences.threshold = threshold
        preferences.validate(); engine.threshold = preferences.threshold
        savePreferences(); resetMonitoring(); schedule(); checkNow()
    }
    private func resetMonitoring() {
        generation += 1; observationGate.reset(); engine.resetSequence()
    }
    private func schedule() {
        timer?.invalidate(); timer = nil
        if preferences.monitorEnabled {
            timer = Timer.scheduledTimer(withTimeInterval: observationGate.delay(at: Date(), interval: preferences.intervalSeconds), repeats: false) { [weak self] _ in
                Task { @MainActor in self?.checkNow() }
            }
            timer?.tolerance = 1
        }
    }
    func checkNow() {
        guard preferences.monitorEnabled, !isChecking, !shutdownRequested else { return }
        isChecking = true
        let stamp = generation
        Task {
            defer {
                isChecking = false
                if stamp != generation && preferences.monitorEnabled && !shutdownRequested { checkNow() }
                else { schedule() }
            }
            let result = await Task.detached(priority: .utility) { Result { try NativeProcesses.capture() } }.value
            guard stamp == generation, preferences.monitorEnabled, !shutdownRequested else { return }
            switch result {
            case .failure(let error):
                monitorError = error.localizedDescription; engine.resetSequence(); observationGate.reset()
                record(action: "snapshot error", result: error.localizedDescription)
            case .success(let snapshot):
                let now = Date()
                totalProcesses = snapshot.records.count; zombieCount = snapshot.zombieCount
                lastCheck = now; monitorError = nil
                // Manual refresh cannot manufacture three five-minute observations.
                let eligible = observationGate.accept(at: now, interval: preferences.intervalSeconds)
                do {
                    let alerts = engine.observe(snapshot, at: now, countTowardConfirmation: eligible)
                    incidents = engine.incidents.sorted { $0.lastSeen > $1.lastSeen }
                    var persisted = true
                    do {
                        guard let store else { throw ToolsetError(message: "Каталог диагностики недоступен.") }
                        try await store.save(incidents)
                        try await store.record(.init(action: "snapshot", result: "Всего процессов: \(snapshot.records.count); zombie: \(snapshot.zombieCount)"))
                        storageError = nil
                    } catch { persisted = false; storageError = error.localizedDescription }
                    if stamp == generation { for incident in alerts { notify(incident, saved: persisted) } }
                }
            }
        }
    }
    func setSleepMode(_ mode: SleepMode) {
        preferences.sleepMode = mode; savePreferences()
        do { try power.set(mode); sleepError = nil }
        catch { sleepError = error.localizedDescription; record(action: "sleep error", result: error.localizedDescription) }
        actualSleep = power.actual
    }
    func setLoginEnabled(_ enabled: Bool) {
        do { try LoginService.set(enabled); notice = nil }
        catch { notice = "Автозапуск: \(error.localizedDescription)" }
        loginStatus = LoginService.status
    }
    func refreshPermissions() {
        loginStatus = LoginService.status
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: notificationsStatus = "Разрешены"
            case .denied: notificationsStatus = "Отключены в настройках macOS"
            case .notDetermined: notificationsStatus = "Разрешение не запрошено"
            @unknown default: notificationsStatus = "Неизвестное состояние"
            }
        }
    }
    func requestNotificationPermission() {
        Task {
            do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
            catch { notice = "Уведомления: \(error.localizedDescription)" }
            refreshPermissions()
        }
    }
    private func notify(_ incident: Incident, saved: Bool) {
        let content = UNMutableNotificationContent()
        content.title = "\(incident.count) zombie: \(incident.parent.name)"
        content.body = saved ? "Проблема подтверждена. Диагностика сохранена. Откройте карточку для просмотра." : "Проблема подтверждена. Не удалось сохранить диагностику — откройте приложение."
        content.sound = .default
        content.userInfo = ["incidentID": incident.id.uuidString]
        let request = UNNotificationRequest(identifier: incident.id.uuidString, content: content, trigger: nil)
        Task {
            do { try await UNUserNotificationCenter.current().add(request) }
            catch { notice = "Не удалось отправить уведомление: \(error.localizedDescription)" }
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["incidentID"] as? String
        Task { @MainActor in
            selectedIncident = id.flatMap(UUID.init(uuidString:)); showDashboard?()
        }
        completionHandler()
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    func revealDiagnostics() {
        if let store { NSWorkspace.shared.open(store.directory) }
    }
    func exportDiagnostics() {
        guard let store else { notice = "Каталог диагностики недоступен."; return }
        let panel = NSSavePanel()
        panel.title = "Экспорт диагностики для IT"
        panel.message = "JSON и TXT содержат имена процессов, PID и пути, включая имя пользователя. Аргументы команд и окружение не включаются."
        panel.nameFieldStringValue = "macos-toolset-diagnostics.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let textURL = url.deletingPathExtension().appendingPathExtension("txt")
        if FileManager.default.fileExists(atPath: textURL.path) {
            let alert = NSAlert(); alert.messageText = "Заменить также TXT-отчёт?"
            alert.informativeText = textURL.path; alert.addButton(withTitle: "Заменить"); alert.addButton(withTitle: "Отмена")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        Task {
            do { try await store.export(to: url); notice = "Сохранены JSON и TXT: \(url.deletingLastPathComponent().path)" }
            catch { storageError = "Экспорт не завершён: \(error.localizedDescription)" }
        }
    }
    private func record(action: String, result: String, parent: ProcessIdentity? = nil) {
        Task {
            do {
                guard let store else { throw ToolsetError(message: "Каталог диагностики недоступен.") }
                try await store.record(.init(parent: parent, action: action, result: result))
            } catch { storageError = "Не удалось сохранить журнал: \(error.localizedDescription)" }
        }
    }
    func canRestart(_ incident: Incident) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: incident.parent.identity.pid) else { return false }
        return app.bundleURL != nil && app.activationPolicy != .prohibited && !app.isTerminated
    }
    func performAction(_ incident: Incident, action: ParentAction) {
        guard busyAction == nil, incident.isActive else { return }
        busyAction = incident.id
        Task {
            defer { busyAction = nil }
            do {
                let target = try await Task.detached { try NativeProcesses.validate(incident) }.value
                let app = NSRunningApplication(processIdentifier: target.identity.pid)
                let bundle = app?.bundleURL
                if action == .restart && !canRestart(incident) { throw ToolsetError(message: "Штатный перезапуск этого процесса недоступен.") }
                let alert = NSAlert()
                let title = action == .force ? "Принудительно завершить" : action == .restart ? "Перезапустить" : "Завершить"
                alert.messageText = "\(title) \(target.name)?"
                alert.informativeText = "Родитель PID \(target.identity.pid)\n\(target.path)\n\nЭто остановит работу родительского процесса. Возможна потеря несохранённых данных и нарушение VPN или связанных служб. Zombie сами уже завершены."
                alert.alertStyle = .warning
                alert.addButton(withTitle: title); alert.addButton(withTitle: "Отмена")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                let confirmed: Incident = { var copy = incident; copy.parent = target; return copy }()
                _ = try await Task.detached { try NativeProcesses.validate(confirmed) }.value
                guard let store else { throw ToolsetError(message: "Сначала необходимо восстановить сохранение диагностики.") }
                try await store.save([confirmed])
                try await store.record(.init(parent: target.identity, action: action.rawValue, result: "Подтверждено пользователем"))
                _ = try await Task.detached { try NativeProcesses.validate(confirmed) }.value
                if action != .force, let app, app.bundleURL != nil, app.activationPolicy != .prohibited {
                    guard app.terminate() else { throw ToolsetError(message: "Приложение отклонило штатное завершение.") }
                } else {
                    try await Task.detached { try NativeProcesses.signal(target, force: action == .force) }.value
                }
                notice = "Ожидание завершения \(target.name)…"
                var exited = false
                for _ in 0..<15 {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    if try await Task.detached(operation: { try NativeProcesses.hasExited(target.identity) }).value { exited = true; break }
                }
                guard exited else { throw ToolsetError(message: "Процесс не завершился за 15 секунд. Принудительное завершение автоматически не выполнялось.") }
                if action == .restart, let bundle {
                    let configuration = NSWorkspace.OpenConfiguration()
                    _ = try await NSWorkspace.shared.openApplication(at: bundle, configuration: configuration)
                }
                notice = action == .restart ? "Приложение перезапущено." : "Родитель завершён. Следующая проверка покажет состояние zombie."
                record(action: action.rawValue, result: notice!, parent: target.identity)
                observationGate.reset(); checkNow()
            } catch {
                notice = error.localizedDescription
                record(action: action.rawValue, result: "Не выполнено: \(error.localizedDescription)", parent: incident.parent.identity)
            }
        }
    }
}

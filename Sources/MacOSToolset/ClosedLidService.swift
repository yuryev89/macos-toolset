import Foundation
import Combine
import ServiceManagement
import ToolsetCore
import ClosedLidSupport
import ClosedLidIPC
import Darwin

@MainActor final class ClosedLidService: ObservableObject {
    @Published private(set) var status = ClosedLidStatus()
    private let service = SMAppService.daemon(plistName: ClosedLidConstants.plist)
    private let intent = ClosedLidClientIntent()
    private var connection: NSXPCConnection?
    private var session: String?
    private var heartbeat: Timer?
    private var mightOwnSession = false
    private var enabling = false
    private var removing = false
    private var hasLocalHelper: Bool { (try? LocalHelperInstallation.isInstalled()) == true }
    var requiresApproval: Bool { !hasLocalHelper && service.status == .requiresApproval }
    var registered: Bool { hasLocalHelper || (service.status != .notRegistered && service.status != .notFound) }
    var title: String {
        switch status.phase {
        case .off: return status.baselineDisabled == true ? "Выключен · системный сон запрещён извне" : "Выключен"
        case .active: return "Активен · батарея и зарядка"
        case .restoring: return "Восстановление сна…"
        case .error: return "Ошибка · требуется проверка"
        case .externalChange: return "Остановлен · настройка изменена извне"
        case .connecting: return "Подключение…"
        case .requiresApproval: return "Требуется разрешение macOS"
        }
    }
    func start(preferredEnabled: Bool) {
        if preferredEnabled { Task { await setEnabled(true) } }
    }
    func openApprovalSettings() { SMAppService.openSystemSettingsLoginItems() }
    func refreshApproval() {
        if intent.enabled && status.phase == .requiresApproval && service.status == .enabled && !enabling {
            Task { await setEnabled(true) }
        }
    }
    private func connect() throws -> NSXPCConnection {
        if let connection { return connection }
        try HelperInstallation.validate(app: Bundle.main.bundleURL, home: URL(fileURLWithPath: NSHomeDirectory()))
        let helperURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/HelperTools/ClosedLidHelper")
        let hash = try CodeIdentity.verifiedHash(at: helperURL, identifier: ClosedLidConstants.service)
        let peer = NSXPCConnection(machServiceName: ClosedLidConstants.service, options: .privileged)
        peer.remoteObjectInterface = NSXPCInterface(with: ClosedLidHelperProtocol.self)
        peer.setCodeSigningRequirement(try CodeIdentity.requirement(identifier: ClosedLidConstants.service, hash: hash))
        peer.invalidationHandler = { [weak self, weak peer] in
            Task { @MainActor in
                guard let self, self.connection === peer else { return }
                self.connection = nil; self.session = nil; self.heartbeat?.invalidate()
                if self.intent.enabled { self.status = ClosedLidStatus(.error, message: "Связь с помощником потеряна. Он должен восстановить сон; включите режим повторно после проверки.") }
            }
        }
        peer.interruptionHandler = { [weak peer] in peer?.invalidate() }
        peer.resume(); connection = peer; return peer
    }
    private func validateManagedSigning() throws {
        try CodeIdentity.requireManagedServiceSignature(at: Bundle.main.bundleURL, identifier: ClosedLidConstants.appIdentifier)
        try CodeIdentity.requireManagedServiceSignature(at: Bundle.main.bundleURL.appendingPathComponent("Contents/Library/HelperTools/ClosedLidHelper"), identifier: ClosedLidConstants.service)
    }
    private func disconnect() {
        let peer = connection; connection = nil; session = nil; peer?.invalidate()
    }
    private func call<T>(_ peer: NSXPCConnection, _ send: @escaping (ClosedLidHelperProtocol, @escaping (Result<T, Error>) -> Void) -> Void) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let gate = CompletionGate()
            let finish: (Result<T, Error>) -> Void = { result in
                if gate.claim() { continuation.resume(with: result) }
            }
            guard let proxy = peer.remoteObjectProxyWithErrorHandler({ finish(.failure($0)) }) as? ClosedLidHelperProtocol else {
                finish(.failure(lidError("Не удалось подключиться к системному помощнику."))); return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                if gate.claim() { peer.invalidate(); continuation.resume(throwing: lidError("Помощник не ответил за 8 секунд. После обновления или перемещения приложения восстановите регистрацию по инструкции README → Helper registration repair. Не удаляйте recovery.json; состояние сна требует проверки.")) }
            }
            send(proxy, finish)
        }
    }
    nonisolated private static func decode(_ data: Data?, _ error: String?) throws -> ClosedLidStatus {
        if let error { throw lidError(error) }
        guard let data else { throw lidError("Помощник вернул пустое состояние.") }
        return try JSONDecoder().decode(ClosedLidStatus.self, from: data)
    }
    private func read(_ peer: NSXPCConnection) async throws -> ClosedLidStatus {
        try await call(peer) { proxy, finish in
            proxy.status { data, error in finish(Result { try Self.decode(data, error) }) }
        }
    }
    func setEnabled(_ enabled: Bool) async {
        if removing || (enabled && enabling) { return }
        if !enabled {
            do { try await shutdown() } catch { if !intent.enabled { status = ClosedLidStatus(.error, message: error.localizedDescription) } }
            return
        }
        if status.phase == .restoring { disconnect() }
        let generation = intent.request(true)
        heartbeat?.invalidate(); enabling = true
        defer { enabling = false }
        status = ClosedLidStatus(.connecting)
        do {
            try HelperInstallation.validate(app: Bundle.main.bundleURL, home: URL(fileURLWithPath: NSHomeDirectory()))
            if try !LocalHelperInstallation.isInstalled() {
                try validateManagedSigning()
                do {
                    if service.status == .notRegistered || service.status == .notFound { try service.register() }
                } catch { if service.status != .requiresApproval { throw error } }
                guard service.status == .enabled else {
                    status = ClosedLidStatus(service.status == .requiresApproval ? .requiresApproval : .error,
                                             message: "Одобрите системный помощник в настройках macOS и вернитесь в приложение.")
                    return
                }
            }
            let peer = try connect()
            mightOwnSession = true
            let response: (String, ClosedLidStatus) = try await call(peer) { proxy, finish in
                proxy.begin { token, data, error in
                    finish(Result {
                        let state = try Self.decode(data, error)
                        guard let token, UUID(uuidString: token) != nil, state.phase == .active else { throw lidError("Помощник не подтвердил активную сессию.") }
                        return (token, state)
                    })
                }
            }
            guard intent.accepts(generation) else {
                // Ending this exact old session cannot disable a newer owner's session.
                _ = try? await end(peer, token: response.0)
                return
            }
            session = response.0; status = response.1
            heartbeat = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                Task { @MainActor in await self?.renew(generation: generation) }
            }
        } catch {
            if intent.accepts(generation) {
                disconnect()
                status = ClosedLidStatus(.error, message: error.localizedDescription)
            }
        }
    }
    private func end(_ peer: NSXPCConnection, token: String) async throws -> ClosedLidStatus {
        try await call(peer) { proxy, finish in
            proxy.end(session: token) { data, error in finish(Result { try Self.decode(data, error) }) }
        }
    }
    private func renew(generation: UInt64) async {
        guard intent.accepts(generation), let peer = connection, let token = session else { return }
        do {
            let result: ClosedLidStatus = try await call(peer) { proxy, finish in
                proxy.renew(session: token) { data, error in finish(Result { try Self.decode(data, error) }) }
            }
            guard intent.accepts(generation) else { return }
            status = result
            if result.phase != .active { heartbeat?.invalidate() }
        } catch {
            guard intent.accepts(generation) else { return }
            heartbeat?.invalidate(); disconnect()
            status = ClosedLidStatus(.error, message: error.localizedDescription)
        }
    }
    func shutdown() async throws {
        let generation = intent.request(false); heartbeat?.invalidate()
        guard mightOwnSession else { disconnect(); status = ClosedLidStatus(); return }
        status = ClosedLidStatus(.restoring)
        if let peer = connection, let token = session {
            if let result = try? await end(peer, token: token), result.phase == .off || result.phase == .externalChange {
                guard intent.generation == generation else { return }
                status = result; mightOwnSession = false; disconnect(); return
            }
        }
        guard intent.generation == generation else { return }
        disconnect() // Forces owner-loss cleanup if a begin was in flight or a reply was lost.
        guard hasLocalHelper || service.status == .enabled else { throw lidError("Помощник отключён в macOS; восстановление сна не подтверждено. Верните ему разрешение и повторите отключение режима.") }
        let peer = try connect()
        for _ in 0..<16 {
            let result = try await read(peer)
            guard intent.generation == generation else { return }
            if result.phase == .off || result.phase == .externalChange {
                guard intent.generation == generation else { return }
                status = result; mightOwnSession = false; disconnect(); return
            }
            if result.phase == .error { throw lidError(result.message ?? "Не удалось восстановить сон.") }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw lidError("Восстановление сна ещё не подтверждено. Повторите отключение режима.")
    }
    func inspect() async throws -> ClosedLidStatus {
        guard try LocalHelperInstallation.isInstalled() || service.status == .enabled else {
            return ClosedLidStatus(service.status == .requiresApproval ? .requiresApproval : .off,
                                   message: "Служба: \(service.status.rawValue)")
        }
        return try await read(connect())
    }
    // Root-only maintenance is an explicit administrator action; normal removal still
    // requires the authenticated helper's recovery barrier in removeHelper().
    func unregisterForAdministrativeRepair() async throws {
        guard geteuid() == 0, let user = getenv("SUDO_USER"), String(cString: user) != "root",
              let home = NSHomeDirectoryForUser(String(cString: user)) else {
            throw lidError("Остановка для восстановления доступна только администратору через repair-helper.sh.")
        }
        try HelperInstallation.validate(app: Bundle.main.bundleURL, home: URL(fileURLWithPath: home))
        if service.status != .notRegistered && service.status != .notFound { try await service.unregister() }
    }
    // This unprivileged command never unregisters a helper or interrupts another lease.
    func registerInstalledHelper() throws {
        try HelperInstallation.validate(app: Bundle.main.bundleURL, home: URL(fileURLWithPath: NSHomeDirectory()))
        try validateManagedSigning()
        guard !mightOwnSession, !enabling, !removing else { throw lidError("Сначала завершите активную сессию приложения.") }
        do { try service.register() }
        catch { if service.status != .requiresApproval { throw error } }
        status = ClosedLidStatus(service.status == .enabled ? .connecting : .requiresApproval,
                                 message: "Регистрация обновлена. При необходимости одобрите помощник в macOS, затем проверьте состояние.")
    }
    func removeHelper() async throws {
        guard !removing else { throw lidError("Удаление помощника уже выполняется.") }
        removing = true
        defer { removing = false }
        try await shutdown()
        // Every removal checks global recovery, even when this process never owned a lease.
        let local = try LocalHelperInstallation.isInstalled()
        guard local || service.status == .enabled else {
            if service.status == .notRegistered { return }
            throw lidError("Для проверки восстановления сна верните помощнику разрешение в macOS.")
        }
        let peer = try connect()
        let restored: ClosedLidStatus = try await call(peer) { proxy, finish in
            proxy.prepareRemoval { data, error in finish(Result { try Self.decode(data, error) }) }
        }
        guard restored.phase == .off || restored.phase == .externalChange else {
            throw lidError("Помощник не подтвердил завершение восстановления сна.")
        }
        if local {
            disconnect()
            status = ClosedLidStatus(.off, message: "Сон восстановлен; локальный помощник подготовлен к удалению. Завершите удаление через uninstall-local-helper.sh с правами администратора.")
            return
        }
        try await service.unregister()
        disconnect()
        status = ClosedLidStatus(.off, message: "Помощник отключён. Защищённая запись подписи сохранена; очистка для новой версии требует администратора.")
    }
}

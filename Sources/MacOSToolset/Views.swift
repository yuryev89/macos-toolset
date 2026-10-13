import SwiftUI
import Charts
import ToolsetCore

@MainActor
struct ToolsetDashboardView: View {
    @ObservedObject var model: AppModel
    @State private var page = 0
    @State private var intervalMinutes = 5.0
    @State private var threshold = 40

    private var activeCount: Int { model.incidents.filter(\.isActive).count }
    private var selected: Incident? { model.incidents.first { $0.id == model.selectedIncident } }
    private var monitorTitle: String {
        if !model.preferences.monitorEnabled { return "Монитор отключён" }
        if model.monitorError != nil { return "Ошибка проверки" }
        if activeCount > 0 { return "Требует внимания" }
        return model.lastCheck == nil ? "Ожидание проверки" : "Монитор работает"
    }
    private var monitorColor: Color {
        if !model.preferences.monitorEnabled { return .secondary }
        return model.monitorError != nil || activeCount > 0 ? .orange : .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center) {
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .font(.system(size: 36)).foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("macOS Toolset").font(.largeTitle.bold())
                    Text("Процессы под наблюдением. Сон — под вашим контролем.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isChecking { ProgressView().controlSize(.small) }
                Button(action: model.checkNow) { Label("Проверить сейчас", systemImage: "arrow.clockwise") }
                    .disabled(model.isChecking || !model.preferences.monitorEnabled)
            }
            HStack(spacing: 12) {
                metric("Монитор процессов", value: monitorTitle, symbol: "waveform.path.ecg", color: monitorColor)
                metric("Zombie · последний снимок", value: model.lastCheck == nil ? "—" : "\(model.zombieCount)", symbol: "exclamationmark.circle", color: model.zombieCount > 0 ? .orange : .secondary)
                metric("Активные инциденты", value: "\(activeCount)", symbol: "doc.text.magnifyingglass", color: activeCount > 0 ? .orange : .secondary)
                metric("Фактический режим сна", value: model.actualSleep.title, symbol: "moon.zzz", color: .accentColor)
            }
            if let error = model.storageError { banner("Не удалось сохранить диагностику", detail: error, isError: true) }
            if let notice = model.notice { banner("Результат действия", detail: notice, isError: false) }
            TabView(selection: $page) {
                monitorPage.tabItem { Label("Монитор и отчёты", systemImage: "list.bullet.rectangle") }.tag(0)
                settingsPage.tabItem { Label("Сон и настройки", systemImage: "slider.horizontal.3") }.tag(1)
            }
            HStack {
                Label("Диагностика хранится только на этом Mac · 30 дней", systemImage: "lock.shield")
                Spacer()
                Text("Без автоматического завершения процессов")
            }.font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(minWidth: 900, idealWidth: 1080, minHeight: 650, idealHeight: 780)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: loadSettings)
        .onChange(of: model.selectedIncident) { id in if id != nil { page = 0 } }
    }

    private func metric(_ title: String, value: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 18, weight: .semibold)).foregroundStyle(color).lineLimit(2)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .leading).frame(height: 66)
        .padding(14).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.07)))
    }

    private var monitorPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Toggle("Мониторинг", isOn: Binding(get: { model.preferences.monitorEnabled }, set: { model.setMonitorEnabled($0) }))
                    .toggleStyle(.switch)
                Spacer()
                if let last = model.lastCheck {
                    Text("Проверено \(last.formatted(date: .abbreviated, time: .standard)) · процессов: \(model.totalProcesses)")
                } else { Text("Успешных проверок пока нет") }
            }.font(.callout)
            if let error = model.monitorError { banner("Проверка не завершена", detail: error, isError: true) }
            HSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Инциденты").font(.headline)
                        Spacer()
                        Text("\(model.incidents.count)").foregroundStyle(.secondary)
                    }.padding(12)
                    Divider()
                    if model.incidents.isEmpty {
                        emptyState(symbol: "checkmark.shield", title: "Инцидентов пока нет", text: "Инцидент появится после трёх проверок подряд с превышением порога у одного родителя.")
                    } else {
                        List(selection: $model.selectedIncident) {
                            ForEach(model.incidents.sorted { $0.lastSeen > $1.lastSeen }) { incident in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(incident.parent.name).font(.headline).lineLimit(1)
                                        Spacer()
                                        Text("\(incident.count)").monospacedDigit().bold()
                                    }
                                    Text("PID \(incident.parent.identity.pid) · \(incident.isActive ? "Активен" : "Закрыт")")
                                        .font(.caption).foregroundStyle(incident.isActive ? Color.orange : .secondary)
                                    Text(incident.lastSeen.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 6).tag(incident.id)
                            }
                        }.listStyle(.sidebar)
                    }
                }.frame(minWidth: 220, idealWidth: 270, maxWidth: 320)
                Group {
                    if let incident = selected { incidentDetail(incident) }
                    else { emptyState(symbol: "doc.text.magnifyingglass", title: "История и диагностика", text: "Выберите инцидент, чтобы увидеть родительский процесс, динамику и доступные действия.") }
                }.frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Button(action: model.exportDiagnostics) { Label("Экспорт для IT…", systemImage: "square.and.arrow.up") }
                Button("Показать локальные файлы", action: model.revealDiagnostics)
                Spacer()
                Text("TXT + JSON · имена, PID, пути, снимки и журнал действий\nБез аргументов команд и окружения; пути могут содержать имя пользователя")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(16)
    }

    private func incidentDetail(_ incident: Incident) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(incident.parent.name).font(.title2.bold()).textSelection(.enabled)
                        Text("Родительский процесс · PID \(incident.parent.identity.pid)")
                            .foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer()
                    Label(incident.isActive ? "Активен" : "Закрыт", systemImage: incident.isActive ? "exclamationmark.circle.fill" : "checkmark.circle")
                        .font(.caption.bold()).foregroundStyle(incident.isActive ? Color.orange : .secondary)
                }
                Text(incident.parent.path.isEmpty ? "Путь недоступен" : incident.parent.path)
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                HStack(spacing: 30) {
                    countLabel("Последнее число", value: incident.count)
                    countLabel("Пиковое число", value: incident.peak)
                }
                if !incident.samples.isEmpty {
                    Chart(Array(incident.samples.enumerated()), id: \.offset) { item in
                        LineMark(x: .value("Время", item.element.time), y: .value("Zombie", item.element.count))
                            .foregroundStyle(Color.orange)
                        PointMark(x: .value("Время", item.element.time), y: .value("Zombie", item.element.count))
                            .foregroundStyle(Color.orange)
                    }.frame(height: 120).chartYScale(domain: .automatic(includesZero: true))
                        .accessibilityLabel("Динамика количества zombie")
                }
                VStack(alignment: .leading, spacing: 6) {
                    detailRow("Первое наблюдение", value: incident.firstSeen.formatted(date: .abbreviated, time: .standard))
                    detailRow("Последнее наблюдение", value: incident.lastSeen.formatted(date: .abbreviated, time: .standard))
                    if let closed = incident.closedAt {
                        detailRow("Закрыт по порогу / родителю", value: closed.formatted(date: .abbreviated, time: .standard))
                        Text("Закрытие не означает, что все zombie исчезли.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                DisclosureGroup("Zombie-потомки: \(incident.children.count) PID") {
                    Text(incident.children.map(String.init).joined(separator: ", "))
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Действия над родителем").font(.headline)
                    Text("Завершение затронет родительское приложение и может прервать связанные службы. Для Cisco это может повлиять на Posture/VPN. Перед действием выполняется свежая проверка и запрашивается подтверждение.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("Завершить родителя…") { model.performAction(incident, action: .terminate) }
                        Button("Принудительно…", role: .destructive) { model.performAction(incident, action: .force) }
                        Button("Перезапустить…") { model.performAction(incident, action: .restart) }
                            .disabled(!model.canRestart(incident))
                    }.disabled(!canAct(incident))
                    if model.busyAction == incident.id {
                        HStack { ProgressView().controlSize(.small); Text("Проверка и выполнение действия…") }.font(.caption)
                    }
                    if !model.canRestart(incident) {
                        Text("Штатный перезапуск доступен только для поддерживаемого GUI-приложения.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                DisclosureGroup("Что попадёт в экспорт") {
                    Text("Снимки процессов, имена и пути, PID, время запуска, количество zombie, динамика, системные сведения, ошибки и журнал действий. Аргументы команд, переменные окружения и содержимое документов не сохраняются. Локальные файлы можно просмотреть перед передачей в IT.")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                }
            }.padding(20)
        }
    }

    private func canAct(_ incident: Incident) -> Bool {
        incident.isActive && model.busyAction == nil && incident.parent.identity.pid > 1 && incident.parent.identity.pid != ProcessInfo.processInfo.processIdentifier
    }
    private func countLabel(_ title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(value)").font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
    private func detailRow(_ title: String, value: String) -> some View {
        HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(value).textSelection(.enabled) }.font(.caption)
    }

    private var settingsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Режим", selection: Binding(get: { model.preferences.sleepMode }, set: { model.setSleepMode($0) })) {
                            ForEach(SleepMode.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.pickerStyle(.radioGroup)
                        Text(sleepDescription).font(.callout).foregroundStyle(.secondary)
                        Label("Сейчас: \(model.actualSleep.title)", systemImage: "moon.zzz").font(.callout.bold())
                        Text("Режим сохраняется и действует до отключения или выхода. Обычные режимы не предотвращают сон при закрытии крышки. Для этого включите отдельный режим ниже. Блокировка экрана остаётся доступной.")
                            .font(.caption).foregroundStyle(.secondary)
                        if let error = model.sleepError { banner("Не удалось применить режим сна", detail: error, isError: true) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                } label: { Label("Управление сном", systemImage: "moon") }
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Работать с закрытой крышкой", isOn: Binding(get: { model.preferences.closedLidEnabled }, set: { model.setClosedLidEnabled($0) }))
                            .disabled(model.closedLid.status.phase == .connecting || model.closedLid.status.phase == .restoring)
                        Label(model.closedLid.title, systemImage: "laptopcomputer").font(.callout.bold())
                        Text("На батарее и зарядке, без внешнего монитора. Mac продолжает выполнять задачи и поддерживать соединения. Запрет действует на системный сон в целом: для обычного сна выключите этот режим. Расход батареи увеличивается; блокировка экрана доступна.")
                            .font(.caption).foregroundStyle(.secondary)
                        if let message = model.closedLid.status.message { Text(message).font(.callout).foregroundStyle(.secondary) }
                        if model.closedLid.requiresApproval { Button("Разрешить помощник в настройках macOS…") { model.closedLid.openApprovalSettings() } }
                        if model.closedLid.registered { Button("Отключить системный помощник…") { model.removeClosedLidHelper() } }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                } label: { Label("Закрытая крышка", systemImage: "laptopcomputer") }
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 20) {
                            Stepper(value: $intervalMinutes, in: 1...60, step: 1) {
                                Text("Интервал: \(Int(intervalMinutes)) мин")
                            }.frame(maxWidth: 260)
                            HStack {
                                Text("Порог zombie:")
                                TextField("40", value: $threshold, format: .number.grouping(.never))
                                    .textFieldStyle(.roundedBorder).frame(width: 80)
                            }
                            Spacer()
                            Button("Применить") {
                                threshold = min(10000, max(1, threshold))
                                model.updateMonitoring(intervalMinutes: intervalMinutes, threshold: threshold)
                            }.disabled(threshold < 1 || threshold > 10000)
                        }
                        Text("Интервал: 1–60 минут. Порог: 1–10 000 zombie у одного родителя. Подтверждение — три успешные проверки подряд. Изменение настроек сбрасывает серию подтверждений.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(8)
                } label: { Label("Мониторинг процессов", systemImage: "waveform.path.ecg") }
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Запуск при входе").font(.headline)
                                Text(model.loginStatus).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Включить") { model.setLoginEnabled(true) }
                            Button("Отключить") { model.setLoginEnabled(false) }
                        }
                        Divider()
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Уведомления").font(.headline)
                                Text(model.notificationsStatus).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Запросить разрешение", action: model.requestNotificationPermission)
                            Button("Обновить статус", action: model.refreshPermissions)
                        }
                        Text("Если macOS требует одобрения, разрешите автозапуск в Системных настройках. Отказ в уведомлениях не останавливает мониторинг и сохранение отчётов.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(8)
                } label: { Label("Интеграция с macOS", systemImage: "gearshape") }
            }.padding(18)
        }
    }
    private var sleepDescription: String {
        switch model.preferences.sleepMode {
        case .off: return "macOS управляет обычным сном компьютера и экрана."
        case .system: return "Компьютер продолжает работу при бездействии; экран может погаснуть."
        case .display: return "Компьютер и экран остаются активными при бездействии."
        }
    }
    private func loadSettings() {
        intervalMinutes = model.preferences.intervalSeconds / 60
        threshold = model.preferences.threshold
        model.refreshPermissions()
    }
    private func emptyState(symbol: String, title: String, text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 38, weight: .light)).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(title).font(.headline)
            Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 370)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func banner(_ title: String, detail: String, isError: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(isError ? Color.orange : .accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.bold())
                Text(detail).font(.callout).textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }.padding(10).background((isError ? Color.orange : .accentColor).opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
    }
}

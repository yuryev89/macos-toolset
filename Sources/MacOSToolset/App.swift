import AppKit
import SwiftUI
import Combine
import ToolsetCore
import ClosedLidSupport

private func stallDiagnosticHeartbeat() { _ = DispatchSemaphore(value: 0).wait(timeout: .now() + 66) }

@main
struct ToolsetApplication {
    static func main() {
        let app = NSApplication.shared
        if let command = CommandLine.arguments.dropFirst().first, command.hasPrefix("--closed-lid-") {
            app.setActivationPolicy(.prohibited)
            let probe = ClosedLidService()
            Task { @MainActor in
                do {
                    if command == "--closed-lid-validate-installation" {
                        try HelperInstallation.validate(app: Bundle.main.bundleURL, home: URL(fileURLWithPath: NSHomeDirectory()))
                        print("Installed app location verified."); exit(0)
                    }
                    if command == "--closed-lid-unregister-for-repair" {
                        try await probe.unregisterForAdministrativeRepair()
                        print("Administrative unregister completed; recovery journal remains intact."); exit(0)
                    }
                    if command == "--closed-lid-register" {
                        try probe.registerInstalledHelper()
                        print(String(decoding: try JSONEncoder().encode(probe.status), as: UTF8.self)); exit(0)
                    }
                    if command == "--closed-lid-status" {
                        let state = try await probe.inspect()
                        print(String(decoding: try JSONEncoder().encode(state), as: UTF8.self)); exit(0)
                    }
                    guard ["--closed-lid-probe", "--closed-lid-probe-crash", "--closed-lid-probe-lease"].contains(command) else { exit(64) }
                    await probe.setEnabled(true)
                    let active = probe.status
                    print(String(decoding: try JSONEncoder().encode(active), as: UTF8.self)); fflush(stdout)
                    guard active.phase == .active else { exit(2) }
                    if command == "--closed-lid-probe-crash" { _exit(0) }
                    if command == "--closed-lid-probe-lease" {
                        // Deliberately stall this diagnostic process, not the user's running app.
                        stallDiagnosticHeartbeat()
                        let expired = try await probe.inspect()
                        print(String(decoding: try JSONEncoder().encode(expired), as: UTF8.self))
                        guard expired.phase == .off else { try? await probe.shutdown(); exit(3) }
                    }
                    try await probe.shutdown()
                    print(String(decoding: try JSONEncoder().encode(probe.status), as: UTF8.self)); exit(0)
                } catch { fputs(error.localizedDescription + "\n", stderr); try? await probe.shutdown(); exit(1) }
            }
            app.run(); return
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var model: AppModel!
    private var observation: AnyCancellable?
    private var terminating = false
    private var terminationReady = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model = AppModel()
        model.showDashboard = { [weak self] in self?.showWindow() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu(); menu.delegate = self; statusItem.menu = menu
        statusItem.button?.setAccessibilityLabel("macOS Toolset")
        observation = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateIcon() }
        }
        let firstLaunch = !model.preferences.onboardingComplete
        updateIcon(); model.start()
        if firstLaunch { showWindow() }
    }
    func applicationDidBecomeActive(_ notification: Notification) { model?.closedLid.refreshApproval() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminationReady { return .terminateNow }
        guard !terminating else { return .terminateLater }
        terminating = true
        Task {
            do {
                try await model.closedLid.shutdown()
                terminationReady = true
                sender.reply(toApplicationShouldTerminate: true)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Восстановление сна не подтверждено"
                alert.informativeText = error.localizedDescription + "\nПри принудительном выходе помощник попробует восстановить настройку после потери связи или истечения сессии."
                alert.addButton(withTitle: "Остаться в приложении")
                alert.addButton(withTitle: "Выйти принудительно")
                let force = alert.runModal() == .alertSecondButtonReturn
                terminationReady = force; terminating = false
                sender.reply(toApplicationShouldTerminate: force)
            }
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) { model?.stop() }
    private func updateIcon() {
        guard let model else { return }
        let issue = model.monitorError != nil || model.storageError != nil || model.incidents.contains(where: \.isActive)
        statusItem.button?.image = NSImage(systemSymbolName: issue ? "exclamationmark.shield" : "square.grid.2x2", accessibilityDescription: "macOS Toolset")
        statusItem.button?.toolTip = "macOS Toolset · \(model.zombieCount) zombie · \(model.actualSleep.title)"
    }
    func menuWillOpen(_ menu: NSMenu) {
        model.refreshPermissions()
        model.closedLid.refreshApproval()
        menu.removeAllItems()
        add(menu, "macOS Toolset", action: #selector(showWindow))
        let status = !model.preferences.monitorEnabled ? "Монитор отключён" : model.monitorError != nil ? "Ошибка проверки процессов" : model.isChecking ? "Проверка процессов…" : "\(model.zombieCount) zombie · \(model.totalProcesses) процессов"
        add(menu, status)
        if let time = model.lastCheck { add(menu, "Проверено: \(time.formatted(date: .omitted, time: .shortened))") }
        menu.addItem(.separator())
        add(menu, "Открыть панель…", action: #selector(showWindow), key: "o")
        let check = add(menu, "Проверить сейчас", action: #selector(checkNow))
        check.isEnabled = model.preferences.monitorEnabled && !model.isChecking
        let toggle = add(menu, "Монитор процессов", action: #selector(toggleMonitor))
        toggle.state = model.preferences.monitorEnabled ? .on : .off
        menu.addItem(.separator())
        for mode in SleepMode.allCases {
            let item = add(menu, mode.title, action: #selector(selectSleep(_:)))
            item.representedObject = mode.rawValue
            item.state = model.actualSleep == mode ? .on : .off
        }
        let lid = add(menu, "Работать с закрытой крышкой", action: #selector(toggleClosedLid))
        lid.state = model.preferences.closedLidEnabled ? .on : .off
        lid.isEnabled = !terminating && model.closedLid.status.phase != .connecting && model.closedLid.status.phase != .restoring
        add(menu, "Крышка: \(model.closedLid.title)")
        if model.closedLid.requiresApproval { add(menu, "Разрешить помощник в macOS…", action: #selector(approveClosedLid)) }
        if model.sleepError != nil { add(menu, "Ошибка управления сном — откройте панель") }
        menu.addItem(.separator())
        add(menu, "Экспорт диагностики…", action: #selector(export))
        add(menu, "Выход", action: #selector(quit), key: "q")
    }
    @discardableResult private func add(_ menu: NSMenu, _ title: String, action: Selector? = nil, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self; if action == nil { item.isEnabled = false }
        menu.addItem(item); return item
    }
    @objc func showWindow() {
        if window == nil {
            let controller = NSHostingController(rootView: ToolsetDashboardView(model: model))
            let w = NSWindow(contentViewController: controller)
            w.title = "macOS Toolset"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 1060, height: 760))
            w.minSize = NSSize(width: 900, height: 660)
            w.isReleasedWhenClosed = false; w.center(); window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    @objc private func selectSleep(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let mode = SleepMode(rawValue: raw) { model.setSleepMode(mode) }
    }
    @objc private func toggleClosedLid() { model.setClosedLidEnabled(!model.preferences.closedLidEnabled) }
    @objc private func approveClosedLid() { model.closedLid.openApprovalSettings() }
    @objc private func toggleMonitor() { model.setMonitorEnabled(!model.preferences.monitorEnabled) }
    @objc private func checkNow() { model.checkNow() }
    @objc private func export() { showWindow(); model.exportDiagnostics() }
    @objc private func quit() { NSApp.terminate(nil) }
}

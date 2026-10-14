import Foundation
import Darwin
import ToolsetCore
import ClosedLidSupport
import ClosedLidIPC

private struct TrustRecord: Codable { var version = 1; var clientHash: String }
private final class Peer: NSObject, ClosedLidHelperProtocol {
    let owner = UUID()
    let state: ClosedLidState
    let queue: DispatchQueue
    init(state: ClosedLidState, queue: DispatchQueue) { self.state = state; self.queue = queue }
    private func encoded() -> Data? { try? JSONEncoder().encode(state.status) }
    func prepareRemoval(reply: @escaping (Data?, String?) -> Void) {
        queue.async {
            do { try self.state.prepareRemoval(); reply(self.encoded(), nil) }
            catch { reply(self.encoded(), error.localizedDescription) }
        }
    }
    func status(reply: @escaping (Data?, String?) -> Void) {
        queue.async { self.state.poll(now: ProcessInfo.processInfo.systemUptime); reply(self.encoded(), nil) }
    }
    func begin(reply: @escaping (String?, Data?, String?) -> Void) {
        queue.async {
            do { let token = try self.state.begin(owner: self.owner, now: ProcessInfo.processInfo.systemUptime); reply(token.uuidString, self.encoded(), nil) }
            catch { reply(nil, self.encoded(), error.localizedDescription) }
        }
    }
    func renew(session: String, reply: @escaping (Data?, String?) -> Void) {
        queue.async {
            do {
                guard let token = UUID(uuidString: session) else { throw lidError("Недействительный идентификатор сессии.") }
                try self.state.renew(session: token, owner: self.owner, now: ProcessInfo.processInfo.systemUptime)
                reply(self.encoded(), nil)
            } catch { reply(self.encoded(), error.localizedDescription) }
        }
    }
    func end(session: String, reply: @escaping (Data?, String?) -> Void) {
        queue.async {
            do {
                guard let token = UUID(uuidString: session) else { throw lidError("Недействительный идентификатор сессии.") }
                try self.state.end(session: token, owner: self.owner); reply(self.encoded(), nil)
            } catch { reply(self.encoded(), error.localizedDescription) }
        }
    }
    func disconnected() { queue.async { self.state.ownerLost(self.owner) } }
}
private final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let state: ClosedLidState
    let queue: DispatchQueue
    init(state: ClosedLidState, queue: DispatchQueue) { self.state = state; self.queue = queue }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // The listener rejects signatures before this delegate is called.
        let peer = Peer(state: state, queue: queue)
        connection.exportedInterface = NSXPCInterface(with: ClosedLidHelperProtocol.self)
        connection.exportedObject = peer
        connection.invalidationHandler = { peer.disconnected() }
        connection.interruptionHandler = { peer.disconnected() }
        connection.resume(); return true
    }
}
@main struct HelperMain {
    static func main() {
        guard geteuid() == 0 else { fputs("ClosedLidHelper must run as an approved system service.\n", stderr); exit(1) }
        do {
            let repair = CommandLine.arguments.dropFirst().first == "--repair-client-trust"
            guard CommandLine.arguments.count == 1 || (repair && CommandLine.arguments.count == 2) else { exit(64) }
            if repair { try ensureServiceUnloaded() }
            let directory = URL(fileURLWithPath: "/Library/Application Support/MacOSToolset/ClosedLid")
            let journal = try RecoveryJournal(directory: directory, secureParents: true)
            try journal.acquireServiceLock()
            let state = ClosedLidState(backend: PowerSettingBackend(), journal: journal)
            // Cleanup must run even if a later update changes the permitted client signature.
            try? state.recover()
            let executable = try CodeIdentity.executableURL()
            let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            guard app.pathExtension == "app" else { throw lidError("Помощник запущен вне установленного приложения.") }
            let currentHash = try CodeIdentity.verifiedHash(at: app, identifier: ClosedLidConstants.appIdentifier)
            if repair {
                try HelperInstallation.validate(app: app, home: URL(fileURLWithPath: NSHomeDirectoryForUser(getenv("SUDO_USER").map { String(cString: $0) } ?? "root") ?? "/var/root"))
                _ = try CodeIdentity.verifiedHash(at: executable, identifier: ClosedLidConstants.service)
                try HelperInstallation.rebind(hash: currentHash, state: state, journal: journal)
                print("Restored the recorded sleep baseline and approved this installed app's exact signature. Recovery data was preserved until restoration succeeded.")
                return
            }
            let pinned: TrustRecord
            if let data = try journal.readRecord("trust.json") {
                pinned = try JSONDecoder().decode(TrustRecord.self, from: data)
                guard pinned.version == 1, pinned.clientHash == currentHash else { throw lidError("Подпись приложения изменилась; требуется административная переустановка помощника.") }
            } else {
                pinned = TrustRecord(clientHash: currentHash)
                try journal.writeRecord(JSONEncoder().encode(pinned), name: "trust.json")
            }
            let queue = DispatchQueue(label: "local.macostoolset.closedlid.state")
            let delegate = ListenerDelegate(state: state, queue: queue)
            let listener = NSXPCListener(machServiceName: ClosedLidConstants.service)
            listener.setConnectionCodeSigningRequirement(try CodeIdentity.requirement(identifier: ClosedLidConstants.appIdentifier, hash: pinned.clientHash))
            listener.delegate = delegate
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 5, repeating: 5)
            timer.setEventHandler { state.poll(now: ProcessInfo.processInfo.systemUptime) }
            timer.resume(); listener.resume()
            withExtendedLifetime((delegate, listener, timer)) { RunLoop.current.run() }
        } catch { NSLog("ClosedLidHelper: %@", error.localizedDescription); exit(1) }
    }
    private static func ensureServiceUnloaded() throws {
        let process = Process(), ended = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "system/" + ClosedLidConstants.service]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in ended.signal() }
        try process.run()
        guard ended.wait(timeout: .now() + 5) == .success else {
            process.terminate(); throw lidError("Не удалось проверить остановку службы.")
        }
        guard process.terminationStatus == 113 else {
            throw lidError("Сначала остановите зарегистрированную службу через repair-helper.sh. Исправление не выполняется при работающей службе.")
        }
    }
}

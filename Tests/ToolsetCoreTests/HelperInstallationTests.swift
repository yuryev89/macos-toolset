import Foundation
import ToolsetCore
import ClosedLidSupport

final class HelperInstallationTests {
    func testOnlyOneHelperCanOwnTheRecoveryDirectory() throws {
        let dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/helper-lock-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        var first: RecoveryJournal? = try RecoveryJournal(directory: dir)
        try first?.acquireServiceLock()
        let second = try RecoveryJournal(directory: dir)
        expectThrows(try second.acquireServiceLock())
        first = nil
        try second.acquireServiceLock()
        // A planted symlink must never become a lock file.
        let bad = dir.appendingPathComponent("bad")
        let unsafe = try RecoveryJournal(directory: bad)
        try FileManager.default.createSymbolicLink(at: bad.appendingPathComponent("helper.lock"), withDestinationURL: dir.appendingPathComponent("helper.lock"))
        expectThrows(try unsafe.acquireServiceLock())
    }
    func testTemporaryAndUninstalledAppsCannotRegister() throws {
        let home = URL(fileURLWithPath: "/Users/test")
        try HelperInstallation.validate(app: URL(fileURLWithPath: "/Applications/macOS Toolset.app"), home: home)
        try HelperInstallation.validate(app: home.appendingPathComponent("Applications/macOS Toolset.app"), home: home)
        for path in ["/private/var/folders/test/AppTranslocation/id/d/macOS Toolset.app", "/Users/test/Downloads/macOS Toolset.app", "/Applications-other/macOS Toolset.app", "/Applications/macOS Toolset.app/Contents", "/Users/other/Applications/macOS Toolset.app"] {
            expectThrows(try HelperInstallation.validate(app: URL(fileURLWithPath: path), home: home))
        }
    }
    func testTrustRepairRestoresBeforeChangingIdentity() throws {
        try withJournal { journal in
            let old = Data(#"{"version":1,"clientHash":"old"}"#.utf8)
            try journal.writeRecord(old, name: "trust.json")
            try journal.save(.init(baseline: false))
            var disabled = true
            let backend = PowerSettingBackend { args in
                if args == ["-g"] { return CommandResult(0, "System-wide power settings:\n SleepDisabled \(disabled ? 1 : 0)\n") }
                disabled = args.last == "1"; return CommandResult(0, "")
            }
            let hash = String(repeating: "a", count: 40)
            let state = ClosedLidState(backend: backend, journal: journal)
            try HelperInstallation.rebind(hash: hash, state: state, journal: journal)
            expectFalse(disabled); expectNil(try journal.load())
            let trust = try JSONSerialization.jsonObject(with: unwrap(journal.readRecord("trust.json"))) as? [String: Any]
            expectEqual(trust?["clientHash"] as? String, hash)
            expectThrows(try state.begin(owner: UUID(), now: 0))
        }
    }
    func testFailedRestorationPreservesOldTrustAndRecovery() throws {
        try withJournal { journal in
            let old = Data(#"{"version":1,"clientHash":"old"}"#.utf8)
            try journal.writeRecord(old, name: "trust.json")
            try journal.save(.init(baseline: false))
            let backend = PowerSettingBackend { args in
                args == ["-g"] ? CommandResult(0, "System-wide power settings:\n SleepDisabled 1\n") : CommandResult(1, "", "denied")
            }
            let state = ClosedLidState(backend: backend, journal: journal)
            expectThrows(try HelperInstallation.rebind(hash: String(repeating: "b", count: 40), state: state, journal: journal))
            try expectEqual(journal.readRecord("trust.json"), old)
            try expectEqual(journal.load()?.baseline, false)
            expectThrows(try HelperInstallation.rebind(hash: "invalid", state: state, journal: journal))
            try expectEqual(journal.readRecord("trust.json"), old)
        }
    }
    private func withJournal(_ body: (RecoveryJournal) throws -> Void) throws {
        let dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/repair-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(RecoveryJournal(directory: dir))
    }
}

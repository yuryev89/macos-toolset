import Foundation
import Darwin
import ToolsetCore
import ClosedLidSupport
final class ClosedLidBackendTests {
    func testPowerCommandsAndParsing() throws {
        var arguments: [[String]] = []
        var result = CommandResult(0, "System-wide power settings:\n SleepDisabled 1\nCurrently in use:\n sleep 1\n")
        let b = PowerSettingBackend { arguments.append($0); return result }
        try expectTrue(b.readDisabled())
        try b.writeDisabled(true); try b.writeDisabled(false)
        expectEqual(arguments, [["-g"], ["disablesleep", "1"], ["disablesleep", "0"]])
        result = CommandResult(0, "System-wide power settings:\n SleepDisabled 0\n")
        try expectFalse(b.readDisabled())
        result = CommandResult(0, "System-wide power settings:\n")
        try expectFalse(b.readDisabled())
        for output in ["", "permission denied", "System-wide power settings:\n SleepDisabled maybe\n", "System-wide power settings:\n SleepDisabled 1\n SleepDisabled 0\n", "System-wide power settings:\nUnknown future field 1\n"] {
            result = CommandResult(0, output); expectThrows(try b.readDisabled())
        }
        result = CommandResult(1, "System-wide power settings:\n")
        expectThrows(try b.readDisabled()); expectThrows(try b.writeDisabled(true))
    }
    func testJournalPersistenceAndUnsafeFiles() throws {
        let parent = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/test-journals").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let dir = parent.appendingPathComponent("journal")
        let j = try RecoveryJournal(directory: dir)
        expectNil(try j.load())
        try j.save(.init(baseline: false))
        try expectEqual(j.load()?.baseline, false)
        let second = try RecoveryJournal(directory: dir)
        try expectEqual(second.load()?.baseline, false)
        let file = dir.appendingPathComponent("recovery.json")
        var st = stat(); expectEqual(lstat(file.path, &st), 0); expectEqual(st.st_mode & 0o777, 0o600)
        try Data(#"{"version":999,"baseline":true}"#.utf8).write(to: file)
        expectThrows(try j.load())
        try Data("broken".utf8).write(to: file); expectThrows(try j.load())
        try FileManager.default.removeItem(at: file)
        let victim = parent.appendingPathComponent("victim")
        try Data("unchanged".utf8).write(to: victim)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: victim)
        expectThrows(try j.load()); expectThrows(try j.save(.init(baseline: true))); expectThrows(try j.clear())
        try expectEqual(String(contentsOf: victim, encoding: .utf8), "unchanged")
        try FileManager.default.removeItem(at: file)
        try j.save(.init(baseline: true)); try j.clear(); expectNil(try j.load())
        chmod(dir.path, 0o777)
        expectThrows(try RecoveryJournal(directory: dir))
        chmod(dir.path, 0o700)
        let link = parent.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: dir)
        expectThrows(try RecoveryJournal(directory: link))
    }
}

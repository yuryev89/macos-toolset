import Foundation
@testable import ToolsetCore
final class DiagnosticsStoreTests {
    func fixture(at date: Date) -> Incident {
        Incident(id: UUID(), parent: .init(identity: .init(pid: 200, seconds: 1)), firstSeen: date, lastSeen: date, count: 40, peak: 40, children: [300], samples: [.init(time: date,count: 40)], lastNotificationAt: date, lastNotificationCount: 40)
    }
    func testSaveLoadPruneAndExport() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = try DiagnosticsStore(directory: dir)
        let now = Date(); let current = fixture(at: now)
        try s.save(current)
        try s.save(fixture(at: now.addingTimeInterval(-31*86400)))
        try s.append(.init(action: "terminate", result: "denied"))
        try expectEqual(try s.load().count, 2)
        try s.prune(at: now)
        try expectEqual(try s.load(), [current])
        try expectEqual(try s.actions().first?.result, "denied")
        let out = dir.appendingPathComponent("export.json")
        try s.export(to: out)
        let data = try Data(contentsOf: out)
        let obj = try unwrap(JSONSerialization.jsonObject(with: data) as? [String:Any])
        expectEqual((obj["incidents"] as? [Any])?.count, 1)
        expectNil(obj["environment"])
        expectNil(obj["arguments"])
        expectTrue(FileManager.default.fileExists(atPath: out.deletingPathExtension().appendingPathExtension("txt").path))
    }
    func testInvalidStoredDataIsAnError() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = try DiagnosticsStore(directory: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: dir.appendingPathComponent("incident-broken.json"))
        expectThrows(try s.load())
    }
}

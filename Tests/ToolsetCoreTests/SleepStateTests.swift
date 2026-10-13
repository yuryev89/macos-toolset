import Foundation
@testable import ToolsetCore
final class SleepStateTests {
    final class Backend: SleepAssertionBackend {
        var held: [UInt32:SleepMode] = [:]
        var failCreate = false
        var failRelease = false
        var next: UInt32 = 0
        func create(_ mode: SleepMode) throws -> UInt32 {
            if failCreate { throw NSError(domain: "test", code: 1) }
            next += 1; held[next] = mode; return next
        }
        func release(_ id: UInt32) throws {
            if failRelease { throw NSError(domain: "test", code: 2) }
            held[id] = nil
        }
    }
    func testChangingModeReleasesOldAndOffReleasesAll() throws {
        let backend = Backend(); let state = SleepState(backend: backend)
        try state.set(.system)
        expectEqual(state.actual, .system)
        try state.set(.display)
        expectEqual(Array(backend.held.values), [.display])
        try state.set(.off)
        expectTrue(backend.held.isEmpty)
        expectEqual(state.actual, .off)
    }
    func testCreateFailureReportsOffAndReleaseFailureKeepsActualMode() throws {
        let backend = Backend(); let state = SleepState(backend: backend)
        try state.set(.system)
        backend.failRelease = true
        expectThrows(try state.set(.display))
        expectEqual(state.actual, .system)
        backend.failRelease = false; backend.failCreate = true
        expectThrows(try state.set(.display))
        expectEqual(state.actual, .off)
        expectTrue(backend.held.isEmpty)
    }
    func testPreferenceDefaultAndOffRoundTrip() throws {
        expectEqual(Preferences().sleepMode, .system)
        var prefs = Preferences(); prefs.sleepMode = .off
        let data = try JSONEncoder().encode(prefs)
        try expectEqual(try JSONDecoder().decode(Preferences.self, from: data).sleepMode, .off)
    }
}

import Foundation
@testable import ToolsetCore

final class ClosedLidStateTests {
    final class Backend: ClosedLidBackend {
        var disabled = false
        var failRead = false
        var failWrite = false
        var afterWriteReadFails = false
        var writes: [Bool] = []
        func readDisabled() throws -> Bool {
            if failRead { throw NSError(domain: "read", code: 1) }; return disabled
        }
        func writeDisabled(_ value: Bool) throws {
            if failWrite { throw NSError(domain: "write", code: 1) }
            writes.append(value); disabled = value
            if afterWriteReadFails { failRead = true }
        }
    }
    final class Journal: ClosedLidJournal {
        var record: RecoveryRecord?
        var failSave = false
        var failClear = false
        func load() throws -> RecoveryRecord? { record }
        func save(_ value: RecoveryRecord) throws {
            if failSave { throw NSError(domain: "save", code: 1) }; record = value
        }
        func clear() throws {
            if failClear { throw NSError(domain: "clear", code: 1) }; record = nil
        }
    }
    func testLeaseBoundaryAndRenewal() throws {
        let b = Backend(), j = Journal(), owner = UUID()
        let s = ClosedLidState(backend: b, journal: j)
        let token = try s.begin(owner: owner, now: 100)
        expectEqual(s.status.phase, .active); expectTrue(b.disabled)
        s.poll(now: 159.999); expectEqual(s.status.phase, .active)
        try s.renew(session: token, owner: owner, now: 150)
        s.poll(now: 209.999); expectTrue(b.disabled)
        s.poll(now: 210); expectFalse(b.disabled); expectNil(j.record)
        _ = try s.begin(owner: owner, now: 300)
        s.poll(now: 360); expectFalse(b.disabled)
    }
    func testOwnershipAndIdempotency() throws {
        let b = Backend(), j = Journal(), owner = UUID()
        let s = ClosedLidState(backend: b, journal: j)
        let token = try s.begin(owner: owner, now: 0)
        try expectEqual(try s.begin(owner: owner, now: 1), token)
        expectEqual(j.record?.baseline, false)
        expectThrows(try s.begin(owner: UUID(), now: 2))
        expectThrows(try s.renew(session: token, owner: UUID(), now: 50))
        expectThrows(try s.end(session: UUID(), owner: owner))
        s.ownerLost(UUID()); expectTrue(b.disabled)
        s.ownerLost(owner); expectFalse(b.disabled)
    }
    func testBaselineAndExternalOverride() throws {
        let b = Backend(), j = Journal(), owner = UUID()
        b.disabled = true
        let s = ClosedLidState(backend: b, journal: j)
        let token = try s.begin(owner: owner, now: 0)
        try s.end(session: token, owner: owner)
        expectTrue(b.disabled); expectEqual(s.status.baselineDisabled, true)
        _ = try s.begin(owner: owner, now: 100)
        b.disabled = false
        s.poll(now: 101)
        expectFalse(b.disabled); expectEqual(s.status.phase, .externalChange)
        expectNil(j.record)
        expectThrows(try s.renew(session: token, owner: owner, now: 102))
    }
    func testFailuresPreserveRecovery() throws {
        let b = Backend(), j = Journal(), owner = UUID()
        let s = ClosedLidState(backend: b, journal: j)
        j.failSave = true
        expectThrows(try s.begin(owner: owner, now: 0)); expectFalse(b.disabled)
        expectTrue(b.writes.isEmpty)
        j.failSave = false
        b.afterWriteReadFails = true
        expectThrows(try s.begin(owner: owner, now: 1))
        expectEqual(j.record?.baseline, false)
        expectEqual(s.status.phase, .error)
        b.afterWriteReadFails = false; b.failRead = false
        s.poll(now: 2); expectFalse(b.disabled); expectNil(j.record)
        let token = try s.begin(owner: owner, now: 10)
        b.failWrite = true
        expectThrows(try s.end(session: token, owner: owner))
        expectEqual(j.record?.baseline, false); expectTrue(b.disabled)
        b.failWrite = false
        s.poll(now: 11); expectFalse(b.disabled); expectNil(j.record)
    }
    func testStartupRecoveryAndFailedClear() throws {
        let b = Backend(), j = Journal()
        b.disabled = true; j.record = RecoveryRecord(baseline: false)
        let s = ClosedLidState(backend: b, journal: j)
        j.failClear = true
        expectThrows(try s.recover()); expectFalse(b.disabled)
        expectThrows(try s.begin(owner: UUID(), now: 0))
        expectEqual(j.record?.baseline, false)
        j.failClear = false; try s.recover(); expectNil(j.record)
        b.failRead = true
        expectThrows(try s.begin(owner: UUID(), now: 0)); expectNil(j.record)
    }
    func testExternalOverrideCleanupFailure() throws {
        let b = Backend(), j = Journal(), owner = UUID()
        b.disabled = true
        let s = ClosedLidState(backend: b, journal: j)
        _ = try s.begin(owner: owner, now: 0)
        b.disabled = false; j.failClear = true
        s.poll(now: 1)
        expectFalse(b.disabled); expectTrue(b.writes.isEmpty)
        expectEqual(j.record?.baseline, false)
        s.ownerLost(owner); s.poll(now: 2)
        expectFalse(b.disabled); expectTrue(b.writes.isEmpty)
        j.failClear = false; s.poll(now: 3)
        expectNil(j.record); expectEqual(s.status.phase, .externalChange)
    }
    func testRemovalRequiresGlobalRecoveryAndBlocksBegin() throws {
        let b = Backend(), j = Journal(), owner = UUID()
        let s = ClosedLidState(backend: b, journal: j)
        let token = try s.begin(owner: owner, now: 0)
        expectThrows(try s.prepareRemoval())
        expectTrue(b.disabled)
        try s.end(session: token, owner: owner)
        try s.prepareRemoval()
        expectThrows(try s.begin(owner: UUID(), now: 1))
        let b2 = Backend(), j2 = Journal()
        b2.disabled = true; j2.record = RecoveryRecord(baseline: false); b2.failWrite = true
        let s2 = ClosedLidState(backend: b2, journal: j2)
        expectThrows(try s2.prepareRemoval()); expectTrue(b2.disabled)
        b2.failWrite = false; try s2.prepareRemoval()
        expectFalse(b2.disabled); expectNil(j2.record)
        expectThrows(try s2.begin(owner: UUID(), now: 2))
    }
    func testOldPreferencesSurvive() throws {
        let old = Data(#"{"monitorEnabled":false,"intervalSeconds":600,"threshold":91,"sleepMode":"off","onboardingComplete":true}"#.utf8)
        var p = try JSONDecoder().decode(Preferences.self, from: old)
        expectFalse(p.closedLidEnabled); expectFalse(p.monitorEnabled)
        expectEqual(p.intervalSeconds, 600); expectEqual(p.threshold, 91)
        expectEqual(p.sleepMode, .off); expectTrue(p.onboardingComplete)
        p.closedLidEnabled = true
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p))
        expectTrue(decoded.closedLidEnabled)
    }
}

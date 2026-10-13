import Foundation
@testable import ToolsetCore
final class IncidentEngineTests {
    let start = Date(timeIntervalSince1970: 1_000_000)
    func snapshot(_ count: Int, parent: ProcessIdentity = .init(pid: 100, seconds: 1)) -> ProcessSnapshot {
        .init(records: [.init(identity: parent)] + (0..<count).map {
            ProcessRecord(identity: .init(pid: Int32(1000 + $0), seconds: 2), parentPID: parent.pid, zombie: true)
        })
    }
    func testInitialPeakUsesAllConfirmationSamples() {
        let e = IncidentEngine()
        for (i, count) in [80, 60, 40].enumerated() { _ = e.observe(snapshot(count), at: start.addingTimeInterval(Double(i)*300)) }
        expectEqual(e.incidents.first?.peak, 80)
    }
    func testEarlyManualRecoveryResetsWithoutCounting() {
        let e = IncidentEngine()
        _ = e.observe(snapshot(40), at: start)
        _ = e.observe(snapshot(0), at: start.addingTimeInterval(60), countTowardConfirmation: false)
        _ = e.observe(snapshot(40), at: start.addingTimeInterval(100), countTowardConfirmation: false)
        expectTrue(e.observe(snapshot(40), at: start.addingTimeInterval(300)).isEmpty)
        expectTrue(e.observe(snapshot(40), at: start.addingTimeInterval(600)).isEmpty)
        expectEqual(e.observe(snapshot(40), at: start.addingTimeInterval(900)).count, 1)
        _ = e.observe(snapshot(0), at: start.addingTimeInterval(950), countTowardConfirmation: false)
        expectEqual(e.incidents.first?.isActive, false)
    }
    func testDetectionRetainsFirstObservationAndSamples() {
        let e = IncidentEngine()
        for i in 0..<3 { _ = e.observe(snapshot(40), at: start.addingTimeInterval(Double(i) * 300)) }
        expectEqual(e.incidents.first?.firstSeen, start)
        expectEqual(e.incidents.first?.samples.count, 3)
    }
    func testReusedPIDDoesNotAttachNewChildrenToOldIncident() {
        let e = IncidentEngine()
        for _ in 0..<3 { _ = e.observe(snapshot(40), at: start) }
        _ = e.observe(snapshot(50, parent: .init(pid: 100, seconds: 999)), at: start.addingTimeInterval(300))
        expectEqual(e.incidents.first?.children, [])
    }
    func testManualRefreshCannotAccelerateConfirmation() {
        var gate = ObservationGate()
        expectTrue(gate.accept(at: start, interval: 300))
        expectFalse(gate.accept(at: start.addingTimeInterval(1), interval: 300))
        expectFalse(gate.accept(at: start.addingTimeInterval(299), interval: 300))
        expectTrue(gate.accept(at: start.addingTimeInterval(300), interval: 300))
        gate.reset()
        expectTrue(gate.accept(at: start.addingTimeInterval(301), interval: 300))
    }
    func testExactlyFortyRequiresThreeChecks() {
        let e = IncidentEngine()
        expectTrue(e.observe(snapshot(40), at: start).isEmpty)
        expectTrue(e.observe(snapshot(40), at: start.addingTimeInterval(300)).isEmpty)
        expectEqual(e.observe(snapshot(40), at: start.addingTimeInterval(600)).first?.count, 40)
    }
    func testBelowThresholdAndFailureResetSequence() {
        let e = IncidentEngine()
        _ = e.observe(snapshot(41), at: start)
        _ = e.observe(snapshot(39), at: start)
        _ = e.observe(snapshot(41), at: start)
        e.resetSequence()
        expectTrue(e.observe(snapshot(41), at: start).isEmpty)
        expectTrue(e.observe(snapshot(41), at: start).isEmpty)
        expectEqual(e.observe(snapshot(41), at: start).count, 1)
    }
    func testParentsAreNotCombinedAndReusedPIDIsNewIdentity() {
        let e = IncidentEngine()
        let a = snapshot(25)
        let b = snapshot(25, parent: .init(pid: 101, seconds: 2))
        for _ in 0..<3 { expectTrue(e.observe(.init(records: a.records + b.records), at: start).isEmpty) }
        _ = e.observe(snapshot(40), at: start)
        _ = e.observe(snapshot(40), at: start)
        expectTrue(e.observe(snapshot(40, parent: .init(pid: 100, seconds: 999)), at: start).isEmpty)
    }
    func testDoublingRateLimitAndRecovery() {
        let e = IncidentEngine()
        for i in 0..<3 { _ = e.observe(snapshot(40), at: start.addingTimeInterval(Double(i)*300)) }
        expectTrue(e.observe(snapshot(40), at: start.addingTimeInterval(900)).isEmpty)
        expectTrue(e.observe(snapshot(80), at: start.addingTimeInterval(1200)).isEmpty)
        expectEqual(e.observe(snapshot(80), at: start.addingTimeInterval(2400)).count, 1)
        expectTrue(e.observe(snapshot(0), at: start.addingTimeInterval(2700)).isEmpty)
        expectEqual(e.incidents.first?.isActive, false)
        expectEqual(e.incidents.first?.count, 0)
    }
    func testHistoryRestoresWithoutDuplicateNotificationAndMissingParentCloses() {
        let first = IncidentEngine()
        for _ in 0..<3 { _ = first.observe(snapshot(40), at: start) }
        let second = IncidentEngine(history: first.incidents)
        for _ in 0..<3 { expectTrue(second.observe(snapshot(40), at: start.addingTimeInterval(900)).isEmpty) }
        _ = second.observe(.init(records: []), at: start.addingTimeInterval(1200))
        expectEqual(second.incidents.filter(\.isActive).count, 0)
    }
}

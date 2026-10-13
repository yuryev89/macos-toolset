import Foundation
import ToolsetCore
final class ClosedLidClientTests {
    func testLateEnableCannotOutliveDisableOrQuit() {
        let intent = ClosedLidClientIntent()
        let enabling = intent.request(true)
        expectTrue(intent.accepts(enabling))
        _ = intent.request(false)
        expectFalse(intent.accepts(enabling)); expectFalse(intent.enabled)
        let second = intent.request(true)
        expectTrue(intent.accepts(second)); expectFalse(intent.accepts(enabling))
        _ = intent.request(false) // Same transition is used before asynchronous application termination.
        expectFalse(intent.accepts(second))
    }
    func testReplyTimeoutRaceCompletesOnlyOnce() {
        let gate = CompletionGate()
        expectTrue(gate.claim()); expectFalse(gate.claim())
        let race = CompletionGate(), queue = DispatchQueue(label: "test.completions")
        var completions = 0
        DispatchQueue.concurrentPerform(iterations: 50) { _ in
            if race.claim() { queue.sync { completions += 1 } }
        }
        expectEqual(completions, 1)
    }
}

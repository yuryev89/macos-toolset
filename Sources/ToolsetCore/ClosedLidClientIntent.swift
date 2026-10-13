import Foundation
/// Confined to the main actor by its caller. A newer intent cancels every older reply.
public final class ClosedLidClientIntent {
    public private(set) var enabled = false
    public private(set) var generation: UInt64 = 0
    public init() {}
    public func request(_ enabled: Bool) -> UInt64 { generation &+= 1; self.enabled = enabled; return generation }
    public func accepts(_ generation: UInt64) -> Bool { enabled && self.generation == generation }
}
/// XPC replies, invalidation and timeouts can race; a continuation has exactly one winner.
public final class CompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    public init() {}
    public func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !completed else { return false }; completed = true; return true
    }
}

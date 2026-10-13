import Foundation
public protocol SleepAssertionBackend {
    func create(_ mode: SleepMode) throws -> UInt32
    func release(_ id: UInt32) throws
}
public final class SleepState {
    private let backend: SleepAssertionBackend
    private var assertion: UInt32?
    public private(set) var actual: SleepMode = .off
    public init(backend: SleepAssertionBackend) { self.backend = backend }
    public func set(_ mode: SleepMode) throws {
        guard mode != actual else { return }
        if let id = assertion {
            try backend.release(id)
            assertion = nil; actual = .off
        }
        guard mode != .off else { return }
        assertion = try backend.create(mode)
        actual = mode
    }
    deinit { if let assertion { try? backend.release(assertion) } }
}

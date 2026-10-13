import Foundation
public struct ObservationGate {
    private var lastAccepted: Date?
    public init() {}
    public mutating func reset() { lastAccepted = nil }
    public mutating func accept(at date: Date, interval: TimeInterval) -> Bool {
        if let previous = lastAccepted, date >= previous, date.timeIntervalSince(previous) < interval { return false }
        lastAccepted = date; return true
    }
    public func delay(at date: Date, interval: TimeInterval) -> TimeInterval {
        guard let lastAccepted, date >= lastAccepted else { return interval }
        return max(0.5, lastAccepted.addingTimeInterval(interval).timeIntervalSince(date))
    }
}

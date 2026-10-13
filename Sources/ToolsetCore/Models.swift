import Foundation

public struct ProcessIdentity: Codable, Hashable, Sendable {
    public var pid: Int32
    public var seconds: UInt64
    public var microseconds: UInt64
    public init(pid: Int32, seconds: UInt64, microseconds: UInt64 = 0) {
        self.pid = pid; self.seconds = seconds; self.microseconds = microseconds
    }
}
public struct ProcessRecord: Codable, Equatable, Sendable {
    public var identity: ProcessIdentity
    public var parentPID: Int32
    public var name: String
    public var path: String
    public var zombie: Bool
    public init(identity: ProcessIdentity, parentPID: Int32 = 1, name: String = "process", path: String = "", zombie: Bool = false) {
        self.identity = identity; self.parentPID = parentPID; self.name = name; self.path = path; self.zombie = zombie
    }
}
public struct ProcessSnapshot: Codable, Sendable {
    public var records: [ProcessRecord]
    public init(records: [ProcessRecord]) { self.records = records }
    public var zombieCount: Int { records.filter(\.zombie).count }
}
public struct CountSample: Codable, Equatable, Sendable {
    public var time: Date
    public var count: Int
}
public struct Incident: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var parent: ProcessRecord
    public var firstSeen: Date
    public var lastSeen: Date
    public var closedAt: Date?
    public var count: Int
    public var peak: Int
    public var children: [Int32]
    public var samples: [CountSample]
    public var lastNotificationAt: Date
    public var lastNotificationCount: Int
    public var isActive: Bool { closedAt == nil }
}
public struct ActionEntry: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var time: Date
    public var parent: ProcessIdentity?
    public var action: String
    public var result: String
    public init(time: Date = Date(), parent: ProcessIdentity? = nil, action: String, result: String) {
        self.time = time; self.parent = parent; self.action = action; self.result = result
    }
}
public enum SleepMode: String, Codable, CaseIterable, Sendable {
    case off, system, display
    public var title: String {
        switch self {
        case .off: return "Запрет сна выключен"
        case .system: return "Не засыпать"
        case .display: return "Не засыпать + экран"
        }
    }
}
public struct Preferences: Codable, Equatable, Sendable {
    public var monitorEnabled = true
    public var intervalSeconds: Double = 300
    public var threshold = 40
    public var sleepMode: SleepMode = .system
    public var onboardingComplete = false
    public var closedLidEnabled = false
    public init() {}
    private enum CodingKeys: String, CodingKey { case monitorEnabled, intervalSeconds, threshold, sleepMode, onboardingComplete, closedLidEnabled }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        monitorEnabled = try values.decode(Bool.self, forKey: .monitorEnabled)
        intervalSeconds = try values.decode(Double.self, forKey: .intervalSeconds)
        threshold = try values.decode(Int.self, forKey: .threshold)
        sleepMode = try values.decode(SleepMode.self, forKey: .sleepMode)
        onboardingComplete = try values.decode(Bool.self, forKey: .onboardingComplete)
        closedLidEnabled = try values.decodeIfPresent(Bool.self, forKey: .closedLidEnabled) ?? false
    }
    public mutating func validate() {
        intervalSeconds = intervalSeconds.isFinite ? min(3600, max(60, intervalSeconds)) : 300
        threshold = min(10000, max(1, threshold))
    }
}

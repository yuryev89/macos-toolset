import Foundation

public final class IncidentEngine {
    public var threshold: Int { didSet { resetSequence() } }
    public private(set) var incidents: [Incident]
    private var streaks: [ProcessIdentity: Int] = [:]
    private var pendingSamples: [ProcessIdentity: [CountSample]] = [:]
    public init(threshold: Int = 40, history: [Incident] = []) {
        self.threshold = max(1, threshold); incidents = history
    }
    public func resetSequence() { streaks.removeAll(); pendingSamples.removeAll() }
    public func observe(_ snapshot: ProcessSnapshot, at time: Date, countTowardConfirmation: Bool = true) -> [Incident] {
        let parents = Dictionary(snapshot.records.filter { !$0.zombie }.map { ($0.identity.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let groups = Dictionary(grouping: snapshot.records.filter(\.zombie), by: \.parentPID)
        var above: Set<ProcessIdentity> = []
        var notifications: [Incident] = []
        // Close stale/changed parents and recovered counts using only a valid snapshot.
        for i in incidents.indices where incidents[i].isActive {
            let identity = incidents[i].parent.identity
            let count = parents[identity.pid]?.identity == identity ? (groups[identity.pid]?.count ?? 0) : 0
            if count < threshold {
                incidents[i].count = count
                incidents[i].lastSeen = time
                incidents[i].closedAt = time
                incidents[i].children = parents[identity.pid]?.identity == identity ? (groups[identity.pid]?.map(\.identity.pid).sorted() ?? []) : []
                incidents[i].samples.append(.init(time: time, count: count))
                incidents[i].samples = Array(incidents[i].samples.suffix(256))
            }
        }
        for (pid, children) in groups {
            guard children.count >= threshold, let parent = parents[pid] else { continue }
            let identity = parent.identity
            above.insert(identity)
            if countTowardConfirmation {
                streaks[identity] = min(3, (streaks[identity] ?? 0) + 1)
                pendingSamples[identity, default: []].append(.init(time: time, count: children.count))
                pendingSamples[identity] = Array(pendingSamples[identity, default: []].suffix(3))
            }
            if let i = incidents.firstIndex(where: { $0.parent.identity == identity && $0.isActive }) {
                incidents[i].count = children.count
                incidents[i].peak = max(incidents[i].peak, children.count)
                incidents[i].lastSeen = time
                incidents[i].children = children.map(\.identity.pid).sorted()
                incidents[i].samples.append(.init(time: time, count: children.count))
                incidents[i].samples = Array(incidents[i].samples.suffix(256))
                if countTowardConfirmation, streaks[identity] == 3,
                   children.count >= incidents[i].lastNotificationCount * 2,
                   time.timeIntervalSince(incidents[i].lastNotificationAt) >= 1800 {
                    incidents[i].lastNotificationAt = time
                    incidents[i].lastNotificationCount = children.count
                    notifications.append(incidents[i])
                }
            } else if countTowardConfirmation && streaks[identity] == 3 {
                let incident = Incident(id: UUID(), parent: parent, firstSeen: pendingSamples[identity]?.first?.time ?? time, lastSeen: time,
                    count: children.count, peak: pendingSamples[identity]?.map(\.count).max() ?? children.count, children: children.map(\.identity.pid).sorted(),
                    samples: pendingSamples[identity] ?? [], lastNotificationAt: time,
                    lastNotificationCount: children.count)
                incidents.append(incident)
                notifications.append(incident)
            }
        }
        streaks = streaks.filter { above.contains($0.key) }
        pendingSamples = pendingSamples.filter { above.contains($0.key) }
        incidents.removeAll { time.timeIntervalSince($0.lastSeen) > 30 * 86400 }
        return notifications
    }
}

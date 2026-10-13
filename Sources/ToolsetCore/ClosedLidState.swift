import Foundation
public protocol ClosedLidBackend {
    func readDisabled() throws -> Bool
    func writeDisabled(_ value: Bool) throws
}
public struct RecoveryRecord: Codable, Equatable {
    public var version = 1
    public var baseline: Bool
    public init(baseline: Bool) { self.baseline = baseline }
}
public protocol ClosedLidJournal {
    func load() throws -> RecoveryRecord?
    func save(_ record: RecoveryRecord) throws
    func clear() throws
}
public struct ClosedLidStatus: Codable, Equatable {
    public enum Phase: String, Codable { case off, active, restoring, error, externalChange, connecting, requiresApproval }
    public var phase: Phase
    public var baselineDisabled: Bool?
    public var message: String?
    public init(_ phase: Phase = .off, baselineDisabled: Bool? = nil, message: String? = nil) {
        self.phase = phase; self.baselineDisabled = baselineDisabled; self.message = message
    }
}
public final class ClosedLidState {
    private let backend: ClosedLidBackend
    private let journal: ClosedLidJournal
    private var pending: RecoveryRecord?
    private var loaded = false
    private var relinquished = false
    private var retiring = false
    private var owner: UUID?
    private var session: UUID?
    private var deadline: TimeInterval = 0
    public private(set) var status = ClosedLidStatus()
    public init(backend: ClosedLidBackend, journal: ClosedLidJournal) {
        self.backend = backend; self.journal = journal
    }
    private func failure(_ error: Error) {
        status = ClosedLidStatus(.error, baselineDisabled: pending?.baseline, message: error.localizedDescription)
    }
    private func denied() -> Error { NSError(domain: "ClosedLid", code: 1, userInfo: [NSLocalizedDescriptionKey: "Недействительная сессия или режим занят другой копией приложения."]) }
    public func recover() throws {
        do {
            if !loaded { pending = try journal.load(); loaded = true }
            guard let record = pending else { return }
            if relinquished {
                // Persist the observed override before cleanup so a restart also respects it.
                try journal.save(RecoveryRecord(baseline: false))
                try journal.clear()
                pending = nil; owner = nil; session = nil
                status = ClosedLidStatus(.externalChange, message: "Настройка сна изменена другой программой. Режим остановлен.")
                return
            }
            status = ClosedLidStatus(.restoring, baselineDisabled: record.baseline)
            if try backend.readDisabled() != record.baseline { try backend.writeDisabled(record.baseline) }
            guard try backend.readDisabled() == record.baseline else { throw NSError(domain: "ClosedLid", code: 2, userInfo: [NSLocalizedDescriptionKey: "Система не подтвердила восстановление сна."]) }
            try journal.clear()
            pending = nil; owner = nil; session = nil
            status = ClosedLidStatus(.off, baselineDisabled: record.baseline)
        } catch { failure(error); throw error }
    }
    public func prepareRemoval() throws {
        guard owner == nil else { throw denied() }
        try recover()
        guard pending == nil else { throw denied() }
        // Serialized with begin: no client can acquire a lease between this reply and unregister.
        retiring = true
    }
    public func begin(owner: UUID, now: TimeInterval) throws -> UUID {
        guard now.isFinite, !retiring else { throw denied() }
        if let session, self.owner != nil, status.phase == .active {
            guard self.owner == owner else { throw denied() }; return session
        }
        do {
            try recover()
            relinquished = false
            let record = RecoveryRecord(baseline: try backend.readDisabled())
            try journal.save(record); pending = record
            if !record.baseline { try backend.writeDisabled(true) }
            guard try backend.readDisabled() else { throw NSError(domain: "ClosedLid", code: 3, userInfo: [NSLocalizedDescriptionKey: "Система не подтвердила запрет сна."]) }
            let token = UUID(); self.owner = owner; session = token; deadline = now + 60
            status = ClosedLidStatus(.active, baselineDisabled: record.baseline)
            return token
        } catch {
            // A successful write followed by a failed reply/read still owns a recovery record.
            self.owner = nil; session = nil
            if pending != nil { try? recover() }
            failure(error); throw error
        }
    }
    public func renew(session: UUID, owner: UUID, now: TimeInterval) throws {
        guard status.phase == .active, self.session == session, self.owner == owner,
              now.isFinite, now < deadline else { throw denied() }
        deadline = now + 60
    }
    public func end(session: UUID, owner: UUID) throws {
        guard self.session == session, self.owner == owner else { throw denied() }
        // Stop lease renewal immediately, even if restoration fails.
        status = ClosedLidStatus(.restoring, baselineDisabled: pending?.baseline)
        try recover()
    }
    public func ownerLost(_ owner: UUID) {
        guard self.owner == owner else { return }
        status = ClosedLidStatus(.restoring, baselineDisabled: pending?.baseline)
        try? recover()
    }
    public func poll(now: TimeInterval) {
        guard status.phase == .active else { if pending != nil || !loaded { try? recover() }; return }
        do {
            // Respect an observed external request to allow sleep; do not reassert or restore over it.
            if try !backend.readDisabled() {
                relinquished = true
                pending = RecoveryRecord(baseline: false)
                owner = nil; session = nil
                try recover()
            } else if now >= deadline {
                status = ClosedLidStatus(.restoring, baselineDisabled: pending?.baseline)
                try recover()
            }
        } catch {
            failure(error)
            // A read failure relinquishes activation and starts restoration retries.
            try? recover()
        }
    }
}

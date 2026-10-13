import Foundation
import AppKit
import IOKit.pwr_mgt
import ServiceManagement
import CSnapshot
import ToolsetCore

struct ToolsetError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
struct NativeProcesses {
    static func capture() throws -> ProcessSnapshot {
        var pointer: UnsafeMutablePointer<TSProcess>?
        var count = 0
        let code = ts_snapshot(&pointer, &count)
        guard code == 0, let pointer else {
            throw ToolsetError(message: "Не удалось прочитать процессы: \(String(cString: strerror(code))) (\(code)).")
        }
        defer { ts_free_snapshot(pointer) }
        let rows = UnsafeBufferPointer(start: pointer, count: count).map { row -> ProcessRecord in
            let name = withUnsafeBytes(of: row.name) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            let path = withUnsafeBytes(of: row.path) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            return ProcessRecord(identity: .init(pid: row.pid, seconds: row.start_seconds, microseconds: row.start_microseconds),
                parentPID: row.ppid, name: name, path: path, zombie: row.zombie != 0)
        }
        return ProcessSnapshot(records: rows)
    }
    static func validate(_ incident: Incident) throws -> ProcessRecord {
        let snapshot = try capture()
        let target = incident.parent
        guard target.identity.pid > 1, target.identity.pid != getpid(), target.identity.seconds != 0,
              let current = snapshot.records.first(where: { $0.identity == target.identity && !$0.zombie }),
              current.name == target.name,
              target.path.isEmpty || current.path == target.path else {
            throw ToolsetError(message: "Процесс исчез, изменился или его идентичность нельзя подтвердить. Обновите список.")
        }
        guard snapshot.records.contains(where: { $0.zombie && $0.parentPID == current.identity.pid }) else {
            throw ToolsetError(message: "У процесса больше нет zombie-потомков. Действие отменено.")
        }
        return current
    }
    static func signal(_ record: ProcessRecord, force: Bool) throws {
        let id = record.identity
        let code = ts_signal_checked(id.pid, id.seconds, id.microseconds, force ? 1 : 0)
        guard code == 0 else {
            throw ToolsetError(message: "Завершение отменено: \(String(cString: strerror(code))) (\(code)). При недостатке прав обратитесь к администратору.")
        }
    }
    static func hasExited(_ identity: ProcessIdentity) throws -> Bool {
        !((try capture()).records.contains { $0.identity == identity && !$0.zombie })
    }
}
final class PowerAssertions: SleepAssertionBackend {
    func create(_ mode: SleepMode) throws -> UInt32 {
        let type = mode == .display ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "macOS Toolset — \(mode.title)" as CFString, &id)
        guard result == kIOReturnSuccess else { throw ToolsetError(message: "macOS не разрешила запрет сна: \(result).") }
        return id
    }
    func release(_ id: UInt32) throws {
        let result = IOPMAssertionRelease(id)
        guard result == kIOReturnSuccess else { throw ToolsetError(message: "Не удалось освободить запрет сна: \(result).") }
    }
}
@MainActor
struct LoginService {
    static var status: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "Включён"
        case .requiresApproval: return "Требует разрешения в настройках macOS"
        case .notRegistered: return "Выключен"
        case .notFound: return "Приложение не найдено системой"
        @unknown default: return "Неизвестное состояние"
        }
    }
    static func set(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
    }
}

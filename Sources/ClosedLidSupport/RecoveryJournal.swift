import Foundation
import Darwin
import ToolsetCore

/// Every operation is relative to a verified, open directory descriptor; no root writes follow symlinks.
public final class RecoveryJournal: ClosedLidJournal {
    private let directoryFD: Int32
    private let owner: uid_t
    public init(directory: URL, secureParents: Bool = false) throws {
        owner = geteuid()
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw lidError("Не удалось открыть корневой каталог журнала.") }
        do {
            let components = directory.pathComponents.dropFirst()
            for (index, component) in components.enumerated() {
                let last = index == components.count - 1
                let mode: mode_t = last || component == "MacOSToolset" ? 0o700 : 0o755
                if mkdirat(fd, component, mode) != 0 && errno != EEXIST { throw lidError("Не удалось создать каталог журнала: \(errno).") }
                let next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else { throw lidError("Небезопасный путь журнала: \(component), errno \(errno).") }
                var info = stat()
                guard fstat(next, &info) == 0 else { close(next); throw lidError("Не удалось проверить каталог.") }
                if last || secureParents {
                    guard info.st_uid == owner, info.st_mode & 0o022 == 0 else { close(next); throw lidError("Каталог журнала имеет неверного владельца или разрешения.") }
                }
                close(fd); fd = next
            }
            directoryFD = fd
        } catch { close(fd); throw error }
    }
    deinit { close(directoryFD) }
    private func checkedFile(_ name: String) throws -> Int32? {
        let fd = openat(directoryFD, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        if fd < 0 && errno == ENOENT { return nil }
        guard fd >= 0 else { throw lidError("Небезопасный файл состояния: \(errno).") }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == owner, info.st_mode & 0o077 == 0, info.st_nlink == 1, info.st_size <= 65536 else {
            close(fd); throw lidError("Неверные права или тип файла состояния.")
        }
        return fd
    }
    public func readRecord(_ name: String) throws -> Data? {
        guard let fd = try checkedFile(name) else { return nil }
        defer { close(fd) }
        var data = Data(), bytes = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &bytes, bytes.count)
            if count < 0 { if errno == EINTR { continue }; throw lidError("Ошибка чтения журнала.") }
            if count == 0 { return data }
            guard data.count + count <= 65536 else { throw lidError("Журнал слишком большой.") }
            data.append(contentsOf: bytes.prefix(count))
        }
    }
    public func writeRecord(_ data: Data, name: String) throws {
        if let existing = try checkedFile(name) { close(existing) }
        let temp = ".\(UUID().uuidString).tmp"
        let fd = openat(directoryFD, temp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw lidError("Не удалось создать временный журнал.") }
        defer { close(fd); unlinkat(directoryFD, temp, 0) }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if written < 0 && errno == EINTR { continue }
                guard written > 0 else { throw lidError("Ошибка записи журнала.") }; offset += written
            }
        }
        guard fsync(fd) == 0, renameat(directoryFD, temp, directoryFD, name) == 0,
              fsync(directoryFD) == 0 else { throw lidError("Не удалось подтвердить сохранение журнала.") }
    }
    public func load() throws -> RecoveryRecord? {
        guard let data = try readRecord("recovery.json") else { return nil }
        let record = try JSONDecoder().decode(RecoveryRecord.self, from: data)
        guard record.version == 1 else { throw lidError("Неизвестная версия журнала.") }; return record
    }
    public func save(_ record: RecoveryRecord) throws { try writeRecord(JSONEncoder().encode(record), name: "recovery.json") }
    public func clear() throws {
        guard let fd = try checkedFile("recovery.json") else { return }
        close(fd)
        guard unlinkat(directoryFD, "recovery.json", 0) == 0, fsync(directoryFD) == 0 else { throw lidError("Не удалось удалить журнал после восстановления.") }
    }
}

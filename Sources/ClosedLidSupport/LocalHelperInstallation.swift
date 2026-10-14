import Foundation
import Darwin

public enum LocalHelperInstallation {
    public static let label = "local.macostoolset.closedlid.local"
    public static let snapshot = "/Library/Application Support/MacOSToolset/LocalHelper.app"
    public static let program = snapshot + "/Contents/Library/HelperTools/ClosedLidHelper"
    public static let plist = "/Library/LaunchDaemons/" + label + ".plist"
    public static func validateRootExecutable(_ url: URL) throws {
        try validateRootDirectory(url.deletingLastPathComponent())
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw lidError("Не удалось проверить защищённый исполняемый файл.") }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & 0o022 == 0, info.st_mode & 0o100 != 0, info.st_nlink == 1 else {
            throw lidError("Исполняемый файл помощника должен принадлежать root и быть защищён от записи.")
        }
        try rejectWritableACL(fd)
    }
    private static func rejectWritableACL(_ fd: Int32) throws {
        guard let acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED) else {
            // On macOS an existing, fstat-checked descriptor reports ENOENT for no ACL.
            if errno == ENOENT { return }
            throw lidError("Не удалось проверить ACL локальной службы: \(errno).")
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var entry: acl_entry_t?
        var selector = ACL_FIRST_ENTRY
        while acl_get_entry(acl, selector.rawValue, &entry) == 0 {
            selector = ACL_NEXT_ENTRY
            var tag = ACL_UNDEFINED_TAG, permissions: acl_permset_t?
            guard let entry, acl_get_tag_type(entry, &tag) == 0, acl_get_permset(entry, &permissions) == 0, let permissions else {
                throw lidError("Некорректная ACL локальной службы.")
            }
            if tag == ACL_EXTENDED_ALLOW {
                for permission in [ACL_WRITE_DATA, ACL_APPEND_DATA, ACL_DELETE, ACL_DELETE_CHILD, ACL_WRITE_ATTRIBUTES, ACL_WRITE_EXTATTRIBUTES, ACL_WRITE_SECURITY, ACL_CHANGE_OWNER] {
                    guard acl_get_perm_np(permissions, permission) == 0 else { throw lidError("ACL разрешает изменение защищённой службы. Требуется административная переустановка.") }
                }
            }
        }
    }
    public static func validateConfiguration(_ data: Data) throws {
        let allowed: Set<String> = ["Label", "Program", "MachServices", "RunAtLoad", "KeepAlive", "ProcessType", "ThrottleInterval"]
        guard data.count <= 65536,
              let values = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              Set(values.keys).isSubset(of: allowed), values["Label"] as? String == label,
              values["Program"] as? String == program,
              let services = values["MachServices"] as? [String: Bool], services == ["local.macostoolset.closedlid": true],
              values["RunAtLoad"] as? Bool == true,
              values["KeepAlive"] as? [String: Bool] == ["SuccessfulExit": false],
              values["ProcessType"] as? String == "Background" else {
            throw lidError("Неверная конфигурация локального помощника. Переустановите его через администратора.")
        }
    }
    public static func isInstalled(at url: URL = URL(fileURLWithPath: plist)) throws -> Bool {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        if fd < 0 && errno == ENOENT { return false }
        guard fd >= 0 else { throw lidError("Небезопасный файл регистрации локального помощника.") }
        defer { close(fd) }
        try validateRootDirectory(url.deletingLastPathComponent())
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & 0o022 == 0, info.st_nlink == 1, info.st_size <= 65536 else {
            throw lidError("Локальная регистрация должна принадлежать root и быть защищена от записи.")
        }
        try rejectWritableACL(fd)
        var data = Data(), bytes = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &bytes, bytes.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw lidError("Не удалось прочитать локальную регистрацию.") }
            if count == 0 { break }
            guard data.count + count <= 65536 else { throw lidError("Локальная регистрация слишком большая.") }
            data.append(contentsOf: bytes.prefix(count))
        }
        try validateConfiguration(data); return true
    }
    public static func validateRootDirectory(_ url: URL) throws {
        var current = URL(fileURLWithPath: "/")
        for component in url.standardizedFileURL.pathComponents.dropFirst() {
            current.appendPathComponent(component)
            var info = stat()
            guard lstat(current.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
                  info.st_uid == 0, info.st_mode & 0o022 == 0 else {
                throw lidError("Путь локального помощника должен состоять из защищённых каталогов root без символических ссылок.")
            }
            let fd = open(current.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw lidError("Не удалось открыть защищённый каталог.") }
            defer { close(fd) }
            try rejectWritableACL(fd)
        }
    }
}

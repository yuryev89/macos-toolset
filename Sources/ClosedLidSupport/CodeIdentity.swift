import Foundation
import Security
import Darwin
public enum CodeIdentity {
    public static func executableURL() throws -> URL {
        // BundleProgram may leave argv[0] relative. Ask the kernel for this process's executable.
        var path = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(getpid(), &path, UInt32(path.count)) > 0 else {
            throw lidError("Не удалось определить путь системного помощника.")
        }
        return URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath()
    }
    public static func verifiedHash(at url: URL, identifier: String) throws -> String {
        var code: SecStaticCode?
        let create = SecStaticCodeCreateWithPath(url as CFURL, [], &code)
        guard create == errSecSuccess, let code else { throw lidError("Не удалось прочитать подпись: \(create).") }
        let valid = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil)
        guard valid == errSecSuccess else { throw lidError("Подпись повреждена или недействительна: \(valid).") }
        var information: CFDictionary?
        let copied = SecCodeCopySigningInformation(code, [], &information)
        guard copied == errSecSuccess, let values = information as? [String: Any],
              values[kSecCodeInfoIdentifier as String] as? String == identifier,
              let hash = values[kSecCodeInfoUnique as String] as? Data else { throw lidError("Неожиданная идентичность исполняемого файла.") }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    public static func requirement(identifier: String, hash: String) throws -> String {
        guard identifier.range(of: #"^[a-zA-Z0-9.-]+$"#, options: .regularExpression) != nil,
              hash.range(of: #"^([a-f0-9]{40}|[a-f0-9]{64})$"#, options: .regularExpression) != nil else { throw lidError("Некорректное требование подписи.") }
        let text = "identifier \"\(identifier)\" and cdhash H\"\(hash)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess else { throw lidError("macOS не принимает требование подписи.") }
        return text
    }
}

import Foundation
import Darwin
import ToolsetCore
public struct CommandResult {
    public var exitStatus: Int32
    public var stdout: String
    public var stderr: String
    public init(_ exitStatus: Int32, _ stdout: String, _ stderr: String = "") { self.exitStatus = exitStatus; self.stdout = stdout; self.stderr = stderr }
}
public func lidError(_ message: String) -> NSError { NSError(domain: "ClosedLid", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
public final class PowerSettingBackend: ClosedLidBackend {
    private let run: ([String]) throws -> CommandResult
    public init(run: @escaping ([String]) throws -> CommandResult = PowerSettingBackend.runPMSet) { self.run = run }
    private func command(_ arguments: [String]) throws -> CommandResult {
        let result = try run(arguments)
        guard result.exitStatus == 0 else { throw lidError("pmset: \(result.stderr.prefix(400)) (\(result.exitStatus))") }
        return result
    }
    public func readDisabled() throws -> Bool {
        let output = try command(["-g"]).stdout
        guard output.utf8.count <= 65536, output.hasSuffix("\n") else { throw lidError("Неполный ответ pmset.") }
        let lines = output.components(separatedBy: .newlines)
        guard lines.first == "System-wide power settings:" else { throw lidError("Неизвестный формат pmset.") }
        var disabled: Bool?
        for raw in lines.dropFirst() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if !raw.hasPrefix(" ") && !raw.hasPrefix("\t") && line.hasSuffix(":") { break }
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            guard fields.count == 2, fields[0] == "SleepDisabled", disabled == nil,
                  fields[1] == "0" || fields[1] == "1" else { throw lidError("Неизвестные системные настройки pmset; изменение отменено.") }
            disabled = fields[1] == "1"
        }
        return disabled ?? false
    }
    public func writeDisabled(_ value: Bool) throws { _ = try command(["disablesleep", value ? "1" : "0"]) }
    public static func runPMSet(_ arguments: [String]) throws -> CommandResult {
        let process = Process(), output = Pipe(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset"); process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin", "LC_ALL": "C", "LANG": "C"]
        process.standardOutput = output; process.standardError = errors
        let ended = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in ended.signal() }
        try process.run()
        let readers = DispatchGroup()
        // The command has no children. Limit both streams before accepting the result.
        final class Capture: @unchecked Sendable { var data = Data(); var overflow = false }
        let out = Capture(), err = Capture()
        for (pipe, capture) in [(output, out), (errors, err)] {
            readers.enter()
            DispatchQueue.global().async {
                defer { readers.leave() }
                while let chunk = try? pipe.fileHandleForReading.read(upToCount: 4096), !chunk.isEmpty {
                    if capture.data.count + chunk.count > 65536 { capture.overflow = true; process.terminate(); break }
                    capture.data.append(chunk)
                }
            }
        }
        if ended.wait(timeout: .now() + 5) == .timedOut {
            process.terminate()
            if ended.wait(timeout: .now() + 1) == .timedOut { kill(process.processIdentifier, SIGKILL) }
            throw lidError("pmset не ответил за 5 секунд; состояние требует проверки.")
        }
        guard readers.wait(timeout: .now() + 1) == .success else { throw lidError("Не удалось дочитать ответ pmset.") }
        guard !out.overflow, !err.overflow else { throw lidError("Ответ pmset слишком большой.") }
        return CommandResult(process.terminationStatus, String(decoding: out.data, as: UTF8.self), String(decoding: err.data, as: UTF8.self))
    }
}

import Foundation

public final class DiagnosticsStore {
    public let directory: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e
    }()
    private let decoder = JSONDecoder()
    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try encoder.encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public func save(_ incident: Incident) throws {
        try write(incident, to: directory.appendingPathComponent("incident-\(incident.id.uuidString).json"))
    }
    public func load() throws -> [Incident] {
        try incidentFiles().map { try decoder.decode(Incident.self, from: Data(contentsOf: $0)) }.sorted { $0.lastSeen > $1.lastSeen }
    }
    private func incidentFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter {
            $0.lastPathComponent.hasPrefix("incident-") && $0.pathExtension == "json"
        }
    }
    public func append(_ action: ActionEntry) throws {
        var entries = try actions(); entries.append(action)
        try write(entries, to: directory.appendingPathComponent("actions.json"))
    }
    public func actions() throws -> [ActionEntry] {
        let url = directory.appendingPathComponent("actions.json")
        if !FileManager.default.fileExists(atPath: url.path) { return [] }
        return try decoder.decode([ActionEntry].self, from: Data(contentsOf: url))
    }
    public func prune(at now: Date) throws {
        let cutoff = now.addingTimeInterval(-30 * 86400)
        for file in try incidentFiles() {
            let incident = try decoder.decode(Incident.self, from: Data(contentsOf: file))
            if incident.lastSeen < cutoff { try FileManager.default.removeItem(at: file) }
        }
        try write(try actions().filter { $0.time >= cutoff }, to: directory.appendingPathComponent("actions.json"))
    }
    public func export(to url: URL) throws {
        let incidents = try load(); let actions = try actions()
        let payload = ExportReport(appVersion: "1.0.0", system: ProcessInfo.processInfo.operatingSystemVersionString,
            timeZone: TimeZone.current.identifier, exportedAt: Date(), incidents: incidents, actions: actions)
        // Export contains only the explicitly typed diagnostic fields, never argv/environment.
        try write(payload, to: url)
        let formatter = ISO8601DateFormatter()
        var text = "macOS Toolset 1.0.0\n\(payload.system)\nЧасовой пояс: \(payload.timeZone)\nЭкспорт: \(formatter.string(from: payload.exportedAt))\n\n"
        for i in incidents {
            text += "\(i.parent.name) — PID \(i.parent.identity.pid)\nПуть: \(i.parent.path)\nНачало процесса: \(i.parent.identity.seconds).\(i.parent.identity.microseconds)\nZombie: \(i.count); максимум: \(i.peak)\nСостояние: \(i.isActive ? "активен" : "закрыт")\nПоследнее наблюдение: \(formatter.string(from: i.lastSeen))\nПотомки: \(i.children.map(String.init).joined(separator: ", "))\nДинамика:\n"
            for sample in i.samples { text += "  \(formatter.string(from: sample.time)): \(sample.count)\n" }
            text += "\n"
        }
        text += "Журнал действий и ошибок:\n"
        for a in actions { text += "\(formatter.string(from: a.time)) | \(a.action) | \(a.result)\n" }
        let textURL = url.deletingPathExtension().appendingPathExtension("txt")
        try Data(text.utf8).write(to: textURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: textURL.path)
    }
}
private struct ExportReport: Codable {
    var appVersion: String
    var system: String
    var timeZone: String
    var exportedAt: Date
    var incidents: [Incident]
    var actions: [ActionEntry]
}

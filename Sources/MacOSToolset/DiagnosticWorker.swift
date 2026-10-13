import Foundation
import ToolsetCore

/// All filesystem work is isolated from the main actor and serialized here.
actor DiagnosticWorker {
    nonisolated let directory: URL
    private var store: DiagnosticsStore?
    init(directory: URL) { self.directory = directory }
    func start() throws -> [Incident] {
        let store = try DiagnosticsStore(directory: directory)
        self.store = store
        try store.prune(at: Date())
        return try store.load()
    }
    private func ready() throws -> DiagnosticsStore {
        guard let store else { throw ToolsetError(message: "Каталог диагностики недоступен.") }
        return store
    }
    func save(_ incidents: [Incident]) throws { for incident in incidents { try ready().save(incident) } }
    func record(_ entry: ActionEntry) throws { try ready().append(entry) }
    func prune() throws { try ready().prune(at: Date()) }
    func export(to url: URL) throws { try ready().export(to: url) }
}

import Foundation
import ToolsetCore

public enum HelperInstallation {
    public static func validate(app: URL, home: URL) throws {
        let app = app.resolvingSymlinksInPath()
        let parent = app.deletingLastPathComponent().path
        guard app.pathExtension == "app", !app.pathComponents.contains("AppTranslocation"),
              parent == "/Applications" || parent == home.appendingPathComponent("Applications").resolvingSymlinksInPath().path else {
            throw lidError("Перенесите macOS Toolset.app в /Applications или ~/Applications, закройте текущую копию и запустите установленное приложение. Помощник нельзя регистрировать из Downloads или App Translocation.")
        }
    }
    public static func rebind(hash: String, state: ClosedLidState, journal: RecoveryJournal) throws {
        _ = try CodeIdentity.requirement(identifier: "local.macostoolset.app", hash: hash)
        try state.prepareRemoval()
        struct Trust: Codable { var version = 1; var clientHash: String }
        try journal.writeRecord(JSONEncoder().encode(Trust(clientHash: hash)), name: "trust.json")
    }
}

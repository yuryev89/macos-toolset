import Foundation
import ClosedLidSupport

final class LocalHelperInstallationTests {
    private var configuration: [String: Any] {
        ["Label": "local.macostoolset.closedlid.local",
         "Program": "/Library/Application Support/MacOSToolset/LocalHelper.app/Contents/Library/HelperTools/ClosedLidHelper",
         "MachServices": ["local.macostoolset.closedlid": true], "RunAtLoad": true,
         "KeepAlive": ["SuccessfulExit": false], "ProcessType": "Background"]
    }
    private func data(_ values: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
    }
    func testConfigurationCannotRunAnUnapprovedExecutable() throws {
        try LocalHelperInstallation.validateConfiguration(data(configuration))
        for (key, value) in [("Program", "/Users/test/Applications/mutable-helper" as Any), ("Label", "another.service" as Any), ("MachServices", ["other.service": true] as Any), ("UserName", "test" as Any), ("ProgramArguments", ["/bin/sh", "-c", "anything"] as Any)] {
            var invalid = configuration; invalid[key] = value
            expectThrows(try LocalHelperInstallation.validateConfiguration(data(invalid)))
        }
        expectThrows(try LocalHelperInstallation.validateConfiguration(Data("broken".utf8)))
    }
    func testUserOwnedAndSymlinkMarkersCannotSelectPrivilegedMode() throws {
        try LocalHelperInstallation.validateRootExecutable(URL(fileURLWithPath: "/bin/launchctl"))
        let dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/local-marker-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("local.plist")
        try expectFalse(LocalHelperInstallation.isInstalled(at: file))
        try data(configuration).write(to: file)
        expectThrows(try LocalHelperInstallation.validateRootExecutable(file))
        expectThrows(try LocalHelperInstallation.isInstalled(at: file))
        expectThrows(try LocalHelperInstallation.validateRootDirectory(dir))
        let link = dir.appendingPathComponent("linked.plist")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        expectThrows(try LocalHelperInstallation.isInstalled(at: link))
    }
}

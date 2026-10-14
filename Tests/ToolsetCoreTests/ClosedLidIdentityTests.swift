import Foundation
import ClosedLidSupport
final class ClosedLidIdentityTests {
    func testExecutablePathIgnoresLaunchdArgumentZero() throws {
        let url = try CodeIdentity.executableURL()
        expectEqual(url.lastPathComponent, "CoreChecks")
        expectTrue(FileManager.default.isExecutableFile(atPath: url.path))
    }
    func testSignedIdentityAndTampering() throws {
        let dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/identity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("client")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: file)
        let sign = Process(); sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["--force", "--sign", "-", "--identifier", "local.macostoolset.app", file.path]
        try sign.run(); sign.waitUntilExit(); expectEqual(sign.terminationStatus, 0)
        let hash = try CodeIdentity.verifiedHash(at: file, identifier: "local.macostoolset.app")
        // A valid ad-hoc signature must not be treated as sufficient for a managed root daemon.
        expectThrows(try CodeIdentity.requireManagedServiceSignature(at: file, identifier: "local.macostoolset.app"))
        expectTrue(hash.count == 40 || hash.count == 64)
        expectThrows(try CodeIdentity.verifiedHash(at: file, identifier: "other.app"))
        expectThrows(try CodeIdentity.requirement(identifier: "local.macostoolset.app", hash: "anything"))
        let requirement = try CodeIdentity.requirement(identifier: "local.macostoolset.app", hash: hash)
        expectTrue(requirement.contains(hash))
        var data = try Data(contentsOf: file); data[4096] ^= 1; try data.write(to: file)
        expectThrows(try CodeIdentity.verifiedHash(at: file, identifier: "local.macostoolset.app"))
    }
}

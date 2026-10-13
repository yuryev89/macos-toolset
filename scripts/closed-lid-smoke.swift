import Foundation
// Explicit opt-in. Close the normal app first so the probe is the only lease owner.
let binary = CommandLine.arguments.dropFirst().first ?? (NSHomeDirectory() + "/Applications/macOS Toolset.app/Contents/MacOS/MacOSToolset")
func run(_ path: String, _ arguments: [String]) throws -> (Int32, String) {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: path); process.arguments = arguments; process.standardOutput = pipe
    try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}
func disabled() throws -> Bool {
    let result = try run("/usr/bin/pmset", ["-g"])
    guard result.0 == 0, result.1.hasPrefix("System-wide power settings:\n") else { throw NSError(domain: "smoke", code: 1) }
    return result.1.components(separatedBy: .newlines).contains { $0.split(whereSeparator: { $0.isWhitespace }).map(String.init) == ["SleepDisabled", "1"] }
}
let baseline = try disabled()
for command in ["--closed-lid-probe", "--closed-lid-probe-crash", "--closed-lid-probe-lease"] {
    print("RUN \(command)"); fflush(stdout)
    let result = try run(binary, [command]); print(result.1); fflush(stdout)
    guard result.0 == 0 else { fputs("Probe incomplete: helper approval or a reported error is pending.\n", stderr); exit(result.0) }
    let limit = Date().addingTimeInterval(15)
    while try disabled() != baseline && Date() < limit { Thread.sleep(forTimeInterval: 0.25) }
    guard try disabled() == baseline else { fputs("FAIL: baseline not restored. Open Toolset and disable the mode; do not unregister the helper yet.\n", stderr); exit(1) }
    print("PASS restored original SleepDisabled=\(baseline)")
}
print("PASS enable/end, client crash and 60-second lease expiry. Physical closed-lid operation remains a separate manual test.")

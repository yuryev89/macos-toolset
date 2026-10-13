import Foundation
import IOKit.pwr_mgt
import ToolsetCore

@main struct SystemSmoke {
    @MainActor static func main() throws {
        func ownedTypes() throws -> [String] {
            var raw: Unmanaged<CFDictionary>?
            let code = IOPMCopyAssertionsByProcess(&raw)
            guard code == kIOReturnSuccess, let raw else { throw ToolsetError(message: "Cannot read assertions: \(code)") }
            let dictionary = raw.takeRetainedValue() as NSDictionary
            let entries = dictionary[NSNumber(value: getpid())] as? [[String: Any]] ?? []
            return entries.compactMap { $0[kIOPMAssertionTypeKey as String] as? String }
        }
        let controller = SleepState(backend: PowerAssertions())
        try controller.set(.system)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        guard try ownedTypes().contains(kIOPMAssertionTypePreventUserIdleSystemSleep) else { fatalError("System assertion missing") }
        print("PASS real system-sleep assertion")
        try controller.set(.display)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let display = try ownedTypes()
        guard display.contains(kIOPMAssertionTypePreventUserIdleDisplaySleep), !display.contains(kIOPMAssertionTypePreventUserIdleSystemSleep) else { fatalError("Display transition failed") }
        print("PASS real display assertion; previous assertion released")
        try controller.set(.off)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        guard try ownedTypes().isEmpty else { fatalError("Assertion leak") }
        print("PASS real off releases owned assertions")
        let snapshot = try NativeProcesses.capture()
        guard snapshot.records.contains(where: { $0.identity.pid == getpid() && $0.identity.seconds > 0 }) else { fatalError("Own process identity missing") }
        print("PASS native Swift bridge snapshot: \(snapshot.records.count) processes")
    }
}

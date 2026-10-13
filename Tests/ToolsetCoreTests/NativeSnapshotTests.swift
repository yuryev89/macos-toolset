import Foundation
import CSnapshot
import Darwin

final class NativeSnapshotTests {
    func testProtectedTargetsRejectBothSignalModes() {
        for pid: Int32 in [-1, 0, 1, getpid()] {
            for force: Int32 in [0, 1] {
                expectEqual(ts_signal_checked(pid, 0, 0, force), EPERM)
            }
        }
    }

    func testInvalidOutputPointerClearsOtherOutput() {
        var count = 42
        expectEqual(ts_snapshot(nil, &count), EINVAL)
        expectEqual(count, 0)
        ts_free_snapshot(nil)
    }
}

import Foundation
var failures = 0
func fail(_ message: String, file: StaticString = #filePath, line: UInt = #line) { failures += 1; print("FAIL \(file):\(line): \(message)") }
func expectEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) rethrows {
    let x = try a(), y = try b(); if x != y { fail("\(x) != \(y)", file: file, line: line) }
}
func expectTrue(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) rethrows { if try !value() { fail("expected true",file:file,line:line) } }
func expectFalse(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) rethrows { try expectTrue(try !value(),file:file,line:line) }
func expectNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { if value != nil { fail("expected nil",file:file,line:line) } }
func expectThrows<T>(_ value: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) { do { _ = try value(); fail("expected error",file:file,line:line) } catch {} }
func unwrap<T>(_ value: T?) throws -> T { guard let value else { throw NSError(domain:"Unwrap",code:1) }; return value }
func run(_ name: String, _ body: () throws -> Void) { let before = failures; do { try body() } catch { fail("\(name): \(error)") }; print("\(failures == before ? "PASS" : "FAIL") \(name)") }
let engine = IncidentEngineTests()
run("initial observations", engine.testDetectionRetainsFirstObservationAndSamples)
run("manual refresh timing", engine.testManualRefreshCannotAccelerateConfirmation)
run("PID history isolation", engine.testReusedPIDDoesNotAttachNewChildrenToOldIncident)
run("initial peak", engine.testInitialPeakUsesAllConfirmationSamples)
run("manual recovery", engine.testEarlyManualRecoveryResetsWithoutCounting)
run("threshold", engine.testExactlyFortyRequiresThreeChecks)
run("resets", engine.testBelowThresholdAndFailureResetSequence)
run("PID reuse", engine.testParentsAreNotCombinedAndReusedPIDIsNewIdentity)
run("debounce and recovery", engine.testDoublingRateLimitAndRecovery)
run("restore history", engine.testHistoryRestoresWithoutDuplicateNotificationAndMissingParentCloses)
let sleep = SleepStateTests()
run("sleep transitions", sleep.testChangingModeReleasesOldAndOffReleasesAll)
run("sleep errors", sleep.testCreateFailureReportsOffAndReleaseFailureKeepsActualMode)
run("preferences", sleep.testPreferenceDefaultAndOffRoundTrip)
let store = DiagnosticsStoreTests()
run("diagnostics", store.testSaveLoadPruneAndExport)
run("invalid diagnostics", store.testInvalidStoredDataIsAnError)
let native = NativeSnapshotTests()
run("protected processes", native.testProtectedTargetsRejectBothSignalModes)
run("native invalid pointer", native.testInvalidOutputPointerClearsOtherOutput)
let lid = ClosedLidStateTests()
run("closed lid lease", lid.testLeaseBoundaryAndRenewal)
run("closed lid ownership", lid.testOwnershipAndIdempotency)
run("closed lid baseline", lid.testBaselineAndExternalOverride)
run("closed lid errors", lid.testFailuresPreserveRecovery)
run("closed lid recovery", lid.testStartupRecoveryAndFailedClear)
run("external cleanup failure", lid.testExternalOverrideCleanupFailure)
run("helper removal barrier", lid.testRemovalRequiresGlobalRecoveryAndBlocksBegin)
run("old preferences", lid.testOldPreferencesSurvive)
let lidBackend = ClosedLidBackendTests()
run("power commands and parsing", lidBackend.testPowerCommandsAndParsing)
run("recovery journal", lidBackend.testJournalPersistenceAndUnsafeFiles)
let identity = ClosedLidIdentityTests()
run("kernel executable path", identity.testExecutablePathIgnoresLaunchdArgumentZero)
run("signed identity and tampering", identity.testSignedIdentityAndTampering)
let lidClient = ClosedLidClientTests()
let installation = HelperInstallationTests()
run("exclusive recovery ownership", installation.testOnlyOneHelperCanOwnTheRecoveryDirectory)
run("installed helper location", installation.testTemporaryAndUninstalledAppsCannotRegister)
run("repair restores before rebind", installation.testTrustRepairRestoresBeforeChangingIdentity)
run("repair preserves failed recovery", installation.testFailedRestorationPreservesOldTrustAndRecovery)
run("late closed-lid enable", lidClient.testLateEnableCannotOutliveDisableOrQuit)
run("XPC reply timeout race", lidClient.testReplyTimeoutRaceCompletesOnlyOnce)
print("Total failures: \(failures)")
exit(failures == 0 ? 0 : 1)

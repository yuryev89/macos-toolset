# macOS Toolset: first-version specification

Date: 2026-09-07
Status: approved by the user and implemented. Verification limitations are listed in [VERIFICATION.md](VERIFICATION.md).

## Purpose and scope

A standalone native Swift/SwiftUI app with a macOS menu bar icon. The first version combines a zombie-process accumulation monitor with sleep prevention controls. The app should launch automatically at login, save preferences, and allow each module to be disabled independently.

The monitor detects persistent zombie accumulation under a single parent and saves useful diagnostic information. It does not promise to identify the root cause of third-party software failures.

The original first-version scope excludes general detection of all unresponsive apps, automatic process termination, an administrative daemon, remote telemetry, cloud synchronization, a plugin marketplace, and a sleep prevention timer. The closed-lid extension described below adds a separate administrative helper.

## Agreed requirements

- Native menu bar interface.
- Monitoring enabled by default, with an off option.
- A check every five minutes.
- Threshold: at least 40 zombies under one parent process.
- Notification after three consecutive successful checks at or above the threshold for the same parent.
- This normally means 10–15 minutes between the onset of a persistent problem and notification.
- Diagnostics saved automatically and locally, with 30-day retention and export for IT.
- Parent termination only after confirmation. Force termination is a separate action with separate confirmation.
- Restart only where the app supports the normal restart procedure.
- Two sleep prevention modes: keep the computer awake while allowing the display to turn off, or keep both awake.
- Mode remains active until manually disabled, without a timer.
- Restore the last selected mode, including off.
- Launch at login enabled by default, with controls in the app and macOS settings.

## Interface

The icon opens a compact menu:

1. Monitoring status: running, disabled, problem detected, or check failed.
2. Total zombie count from the last successful check, check time, and number of affected parents.
3. Access to incidents and reports.
4. Mutually exclusive sleep choices: off, keep computer awake, or keep computer and display awake.
5. Settings, diagnostic export, and quit.

A notification opens the corresponding incident card rather than acting on a process. The card shows the parent, PID, path, zombie count, trend, observation times, and data freshness. Available actions are saving a report, terminating the parent, force termination, and restarting a supported GUI app.

Confirmation explains that terminating the parent may interrupt its work and affect related apps. For Cisco components, this may affect Posture/VPN; the app does not promise that terminating a component is safe for connectivity.

The first version's interface is in Russian. The working name is macOS Toolset. This specification uses English descriptions of the controls.

## Process monitor

### Data collection

The first snapshot is taken on launch or when the module is enabled; subsequent snapshots occur every five minutes. Snapshots do not overlap. Collection uses system APIs inside the app and does not launch a separate shell or `ps` for each poll. This reduces dependence on starting new processes when resources are scarce.

A zombie is identified by process state, not its name, lifetime, or low CPU usage. Data is grouped by parent. Process identity includes PID and start time; path and name provide display information and additional validation.

The process list may change while being read. Entries that disappear are skipped. Insufficient access or failure to obtain a reliable snapshot is reported as an error rather than a zero zombie count.

### Confirmation and recovery

A threshold counter is maintained for each parent identity. A successful check below the threshold resets it. A snapshot error, app restart, disabling monitoring, or changing the threshold or interval also resets the sequence: stale or incomplete data cannot confirm a new incident.

After the computer wakes, one fresh snapshot is taken without replaying missed polls; confirmation starts again. Saved incident history remains available.

The third qualifying check opens an incident and sends a notification. Further successful snapshots update history without duplicate notifications. Significant deterioration means the count has doubled since the last notification for that incident; repeat notifications are limited to one every 30 minutes.

A successful snapshot below the threshold closes the incident on that basis. This does not mean every zombie has disappeared. A parent disappearing closes its incident, while the overall check separately determines whether zombies remain under other parents.

The threshold and interval are configurable; defaults are 40 and five minutes. The first version always requires three confirmations.

## Process actions

A zombie has already exited; sending it a kill signal does not remove its entry. Normally, its parent must collect its status through `wait`/`waitpid`; after the parent exits, the system handles orphaned processes. The app therefore offers no ineffective action to kill a zombie.

Before acting, the app takes a fresh snapshot and revalidates the PID, start time, available executable information, and presence of zombie children. A process that disappeared or changed cannot be terminated from a stale incident card. If identity cannot be verified, the action is canceled. A changed target requires new confirmation.

Normal termination comes first: an app termination request for a recognized GUI app, or a process termination request for an individual process. The app displays the pending result and checks it without blocking the interface. If the process has not exited after 15 seconds, the action is reported as incomplete; force termination is never automatic.

Force termination is separately available after fresh validation and explicit confirmation. Signals are not sent to process groups, all processes sharing a name, or PIDs found through partial matches.

PID 0, PID 1, and the utility's own process are invalid targets. Process actions run with the current user's permissions. If access is insufficient, the app records the refusal and explains that an administrator is needed. The process action module neither runs `sudo` nor installs a privileged helper.

Normal restart in the first version applies only to recognized GUI apps that can be reopened through their bundles. After confirmation, termination is requested first; reopening happens only after confirmed exit. Arbitrary daemons, including `cscan`, are not restarted by replaying arguments or invoking unknown service commands.

Revalidation reduces PID reuse risk but does not make validation and signal delivery completely atomic. Implementation should use the most reliable supported target identification and explicitly account for the remaining limitation.

## Sleep control

The module stores one of three mutually exclusive states: off, prevent idle system sleep, or prevent both idle system sleep and idle display sleep.

On first launch, with no saved selection, the computer is kept awake while the display may turn off. Subsequent launches restore the last selection, including off. This default is visible in the menu and can be changed immediately.

Sleep prevention has no timer and continues until the user changes the mode or quits. The saved mode is enabled again on the next launch. Changing modes releases the previous system assertions. On exit, the app releases the sleep assertions it owns.

The ordinary idle-sleep module does not promise to prevent sleep on lid closure, critically low battery, an explicit user Sleep command, or other forced system conditions. It does not disable screen locking or change macOS security settings.

If a system assertion fails, the menu shows the actual state and the error rather than only the user's intended selection.

## Architecture

- App/Menu UI: menu, incident cards, preferences, and confirmations.
- ProcessSnapshotProvider: snapshots and process identity validation through system APIs.
- ProcessMonitor: scheduling, grouping, confirmation counters, and incident lifecycle.
- NotificationCoordinator: notifications, duplicate suppression, and navigation to incidents.
- DiagnosticsStore: local history, retention, and export.
- ProcessActionService: target validation, confirmed actions, and result tracking.
- SleepController: acquisition and release of app-owned sleep assertions.
- Preferences/LaunchAtLogin: saved preferences and reconciliation with actual macOS login-item status.

Monitoring and sleep modules are independent. Failure in one does not disable the other. Background work does not block the UI. Only preferences, status display, and local logging are shared.

New tools are separate modules with explicit interfaces. Dynamic plugin loading and a general-purpose framework are unnecessary in the first version.

## Diagnostics and storage

Data is stored in the app's user Application Support directory. It remains local; there is no server access or telemetry.

Saved fields include app and macOS versions, snapshot time and time zone, available total process count, parent identity, name and path, zombie child PIDs and states, count trends, read errors, and a log of confirmed actions and their results.

Command arguments, environment variables, memory contents, credentials, and user document contents are not stored. A path may include the username; the report contents can be inspected before sharing with IT.

Export includes a readable text report and structured JSON. Writes are atomic. Data older than 30 days is removed on launch and no more than once per day; the app does not remove user-exported copies. Storage failures are displayed explicitly: a notification does not claim a report was saved when writing failed.

## Launch at login and permissions

On first launch, the app asks macOS to register launch at login and requests notification permission. The default preference is enabled; a system refusal or user disabling it is shown as the actual state. The app does not bypass system confirmation or repeatedly re-enable explicitly disabled launch at login.

Denying notifications does not stop monitoring or report storage: the warning remains in the menu. Ordinary operation requires no administrator privileges.

## Implementation verification

Automated checks with synthetic snapshots and controlled clocks cover:

- Counts of 39, 40, and 41 zombies; independent parents; three consecutive qualifying checks.
- Sequence reset after an error, lower count, sleep, or preference change.
- Duplicate suppression, doubled count, and notification rate limiting.
- Process disappearance, PID reuse, access denial, and canceled confirmation.
- No automatic force termination or restart of unrecognized services.
- Sleep mode changes, assertion release, and restoration of the off state.
- Disk failures, retention, export, and exclusion of arguments and environment variables.

Manual macOS checks cover:

- Icon, preferences, notifications, and opening the corresponding incident card.
- Launch at login and disabling it.
- Both idle-sleep modes and restoration of normal behavior after disabling or quitting.
- A small controlled fixture with zombie children, confirmed termination, and verified cleanup. Real Cisco and other production services are not test targets.

## Acceptance criteria

These criteria define the intended outcome; they do not claim all manual checks have passed. See [VERIFICATION.md](VERIFICATION.md) for actual results.

The app installs and runs as a native macOS app. At the agreed thresholds, monitoring creates an incident, notification, and exportable diagnostics without generating excessive child processes. No processes are terminated without user confirmation. Both idle-sleep modes work and release their assertions correctly. Errors are reported accurately and independently per module. Automated scenarios and manual scenarios on the user's Mac are verified.

## Technical basis

[Apple: wait/waitpid](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/wait.2.html).

Before implementation, specific system APIs, deployment targets, and packaging are checked against the installed macOS/SDK and current Apple documentation. This does not change the agreed app behavior.

## Extension dated 2026-10-13: closed-lid operation

The original sleep control limitation applies to ordinary IOKit idle assertions. A separate closed-lid mode extends the app with an app-managed global `SleepDisabled` setting and an approved root LaunchDaemon. The ordinary process monitor remains unprivileged; administrative access is limited to controlling `SleepDisabled`.

The helper authenticates the app, pins its approved identity, records the original setting in a durable recovery journal, and holds an expiring client lease. It restores the setting when the session ends, expires, or needs crash recovery. This mode is intended for battery and AC operation without an external monitor, but end-to-end and physical verification are still pending. See [closed-lid operation](README.md#closed-lid-operation), [verification](VERIFICATION.md), and the [helper upgrade procedure](RELEASING.md#sleephelper-acceptance-and-upgrades).

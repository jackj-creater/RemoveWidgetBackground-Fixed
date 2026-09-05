# Remove Widget Background

Remove the background of any app widgets on the home screen.

## Candidate build: 2.1.3~test2

The diagnostic1 device capture on iOS 17.1.1 overlapped a user-confirmed 1–2 second
black flash. Recorded host backgrounds were clear, effect views hidden, and eight
persisted snapshot updates suppressed. This narrows investigation but does not
identify the black pixels: the report samples every half second and cannot inspect
remote rendered contents or every transition layer.

This candidate makes one rendering change: isolate the per-thread removal flag
and rectangle counters for each nested RBLayer display, restoring the parent state
in `@finally`. Previously a child could inherit its parent's counter, then erase the
parent's removal state on return; non-target children could inherit removal too.
Tests exercise target/non-target nesting, exceptions, and consecutive displays.
Actual nesting during the reported flash has NOT been captured. This is a code
correctness fix and a device-test candidate, not a confirmed visual fix. Rectangle
selection order, snapshot policy, and SpringBoard background hooks are unchanged.

The existing opt-in diagnostics remain available:

Version 2.1.2 still shows a black widget background for 1–2 seconds when returning
from an app. The cause has not been verified on the affected device. This build
includes an explicitly started, 30-second SpringBoard capture. Compilation and
state-isolation tests are not validation of the visual fix.

1. Install the diagnostic package and respring using the preference pane.
2. In Settings → Remove Widget Background, tap “记录组件黑底（30 秒）”, then “开始”.
3. Return home, tap Weather or Fitness to open its app, then return home again.
4. After 30 seconds, reopen the preference pane and tap “导出诊断”.

The report records host lifecycle events, snapshot suppression, background mode
requests, and bounded public view/layer state for the host and nearby containers.
It does not read widget text, screenshots, image pixels, or remote scene contents.
There is no automatic upload. Sampling runs every half second only during the
capture, stops at 30 seconds or the report-size limit, and logs changed states.
The report is written to `/var/mobile/Library/Logs/RemoveWidgetBackground-diagnostic.txt`.
Each capture replaces the previous report. Runtime capture/export on RootHide
still needs device validation. An unchanged report cannot rule out a background
embedded inside a remote rendered surface.

The inherited implementation includes upstream v2.1.1 preference loading,
early target marking, persisted-snapshot suppression, material cleanup, and
explicit light/dark appearance. These are attempted mitigations, not confirmed
solutions to the remaining flash. The experimental container hook remains absent.

App widgets are built with SwiftUI.
Since it's not an easy job to recognize the background view, we managed to remove them by restricting the size of drawing commands.

It works pretty well with our [Colorful Wallpaper X](https://havoc.app/package/colorfulx). **Enjoy it!**

## Features

- Remove the background of some system widgets.
- Remove the background of specified app widgets.
- Force widgets to use dark mode.

Note that **not all** app widgets are supported: some apps may draw their widgets entirely.
Do not send feedback email to us if you just find some incompatible app widgets. Thank you!

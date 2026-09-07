# Remove Widget Background

Remove the background of any app widgets on the home screen.

## Candidate build: 2.1.3~test6

Test5 removed the black background on the affected device, confirming the
two-rectangle transition diagnosis, but the whole widget disappeared for 1–2
seconds because neither full-size shape remained. Test6 keeps the transparent
test5 renderer behavior and adds a SpringBoard transition bridge: each selected
host caches its last stable transparent snapshot locally, shows that view when
the renderer enters the repeated two-rectangle phase, and fades it out when the
same renderer returns to a normal rectangle count. A three-second fallback always
removes the overlay. The snapshot is held only in memory and is never added to the
diagnostic export. Device validation is still required.

## Previous candidate: 2.1.3~test5

Diagnostic4 captured the affected iOS 17.1.1 return transition. Target recognition
remained enabled and the render layer remained nonopaque. About 0.65 seconds after
the widget hosts reappeared, rendering changed from the normal four full-size
rectangles to a repeated two-rectangle form. Both rectangles were 364 x 170. The
upstream iOS 17 heuristic retained rectangle 1 and removed rectangle 2 on every
such frame, matching the user's observation that widget content stayed visible
while the original background returned.

Test5 remembers the previous large-rectangle count per RBLayer. After a layer has
produced exactly two full-size rectangles, its next repeated two-rectangle frame
also removes rectangle 1. Rectangle 2 continues to be removed by the existing
rule. The first transition frame remains unchanged; later repeated frames remove
both full-size rectangles. Ordinary four-rectangle rendering retains the upstream
keep/drop sequence. Automated tests cover both sequences. This is a device-test
candidate, not yet a confirmed fix.

The diagnostic4 capture remains available in test5.

## Previous diagnostic: 2.1.3~diagnostic4

Diagnostic3 confirmed that two drawing processes received the capture request,
but both were sandboxed from writing a shared report file. Diagnostic4 adds a
compact Darwin notification-state channel from each drawing process to
SpringBoard. SpringBoard polls it every 25 ms and records target recognition,
large-rectangle count, kept-position mask, size-order hash, and layer opacity.
This transport does not require drawing processes to write files and carries no
widget content.

Diagnostic2 exported `Renderer reports found: 0` on the affected device. The
capture was incorrectly limited to processes whose bundle identifier begins with
the WidgetRenderer prefix even though this tweak's iOS 17 render hooks are also
installed in `chronod`. Diagnostic3 starts the same bounded drawing capture in
both process types. It attempts an actual report write instead of relying on a
directory permission preflight, and SpringBoard records whether a drawing process
started successfully or could not write its report.

The affected iOS 17.1.1 device showed no visible improvement with test2. During
both SpringBoard captures, the user saw the widget's normal background return for
1–2 seconds while its content remained visible. Sampled host backgrounds stayed
clear, effect views stayed hidden, and every recorded persisted-snapshot update
was suppressed. This rules out test2 as an effective visual fix and shifts the
next measurement to the widget renderer.

Diagnostic3 keeps test2 rendering behavior. During the explicitly started,
bounded capture it also records, inside each active WidgetRenderer process:

- whether the scene and cached window state identify the widget as selected;
- the dimensions and order of large rectangles passed to the removal heuristic;
- whether each rectangle was kept or replaced with an empty rectangle.

Renderer reports contain no widget text, images, pixels, screenshots, or display-
list contents. They are capped, written only during the capture, and merged with
the SpringBoard report by the export button. This build is diagnostic only.

## Previous candidate: 2.1.3~test2

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

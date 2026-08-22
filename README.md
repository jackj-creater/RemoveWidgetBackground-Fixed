# Remove Widget Background

Remove the background of any app widgets on the home screen.

## iOS 17 fix (v2.1.2)

- Include the upstream v2.1.1 sandbox preference fix so each iOS 17 WidgetRenderer receives the selected-widget, appearance, and drawing-threshold settings before rendering.
- Mark selected widgets before `UIWindow` and `CHUISWidgetHostViewController` run their original initialization paths, closing the first-frame race during automatic refreshes.
- Preserve the host transparency decision while iOS temporarily clears widget metadata during a scene transition.
- Keep SpringBoard from briefly replacing a transparent live widget with an opaque persisted snapshot during automatic Weather and Fitness refreshes.
- Reduce the experimental snapshot hook surface and retain the upstream iOS 17 drawing-command filter.
- Remove the experimental `SBHWidgetContainerView` hook introduced in v2.0.6 because private SpringBoard layouts differ across iOS 17 builds and can trigger safe mode.
- Keep the host background disabled while iOS updates live widget content or restores widgets after unlock.
- Prevent the iOS 17 widget host from recreating its opaque black material while SpringBoard restores widgets after unlock.
- Make the WidgetRenderer window non-opaque as soon as widget metadata becomes available, preventing a temporary black first frame.
- Remove a late-created SpringBoard material background both when the widget is attached and before its first layout.
- Use an explicit light appearance when **Force Dark Mode** is off and a dark appearance when it is on.
- Find nested material views after layout so widget backgrounds are also removed from Today View.
- Detect WidgetKit scenes by capability, allowing newer iOS 17 scene subclasses to work.

App widgets are built with SwiftUI.
Since it's not an easy job to recognize the background view, we managed to remove them by restricting the size of drawing commands.

It works pretty well with our [Colorful Wallpaper X](https://havoc.app/package/colorfulx). **Enjoy it!**

## Features

- Remove the background of some system widgets.
- Remove the background of specified app widgets.
- Force widgets to use dark mode.

Note that **not all** app widgets are supported: some apps may draw their widgets entirely.
Do not send feedback email to us if you just find some incompatible app widgets. Thank you!

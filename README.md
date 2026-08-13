# Remove Widget Background

Remove the background of any app widgets on the home screen.

## iOS 17 fix (v2.0.4)

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

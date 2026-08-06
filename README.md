# Remove Widget Background

Remove the background of any app widgets on the home screen.

## iOS 17 fix (v2.0.1)

- Respect the **Force Dark Mode** preference instead of forcing every widget window to dark mode.
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

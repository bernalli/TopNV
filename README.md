# topNV

Hide the MacBook notch and round the screen corners (macOS menu bar app).

topNV paints the menu-bar strip of every notched display black, so the notch blends into
the bar. It can also round the four corners of the screen. It lives in the menu bar only
(no Dock icon) and needs no Screen Recording or Accessibility permission.

## How it works

topNV never reads or changes the wallpaper. Instead it places a borderless, opaque, black,
click-through window over the menu-bar strip, one window level above the desktop picture
and below every other window. The system menu bar draws on top of that window, so it
appears black with readable and clickable items.

Because the wallpaper itself is untouched, this works with any wallpaper, including
animated and dynamic ones, and it survives wallpaper changes without doing anything.

Rounded corners are four small transparent windows per display, each with a black inverted
quarter circle, placed above the menu bar and the Dock. They ignore the mouse.

The overlay windows are rebuilt when displays change, when the active Space changes, after
wake from sleep, and when a setting changes.

## Settings

Click the menu-bar icon:

- **Hide notch**: black menu bar on notched displays (default on).
- **Round corners**: rounded screen corners (default on).
- **Corner radius**: 0 to 30 points, applied live (default 10).
- **Corners on all displays**: round corners on external displays too (default: built-in
  display only).
- **Launch at login**: registers the app as a login item. If macOS asks for approval, allow
  it in System Settings > General > Login Items.
- **Hide menu bar icon**: hide the icon while topNV keeps running. Open topNV again to
  bring it back.
- **Quit topNV**.

## Build and install

Requirements: macOS 14 or later, Xcode command-line tools with Swift 5.9 or later.

```sh
scripts/bundle.sh
mv build/topNV.app /Applications/
open /Applications/topNV.app
```

`scripts/bundle.sh` builds the release executable with SwiftPM, assembles
`build/topNV.app` and signs it ad hoc. To bundle an executable you already built (for
example with `xcodebuild`), set `TOPNV_EXECUTABLE` to its path.

Run the tests with `swift test`, or with
`xcodebuild -scheme topNV -destination 'platform=macOS' test`.

## Limitations

- The menu bar turns black only on displays with a notch. Other displays keep their normal
  menu bar.
- In full-screen apps the black bar is not visible, as any desktop-level window is covered
  there; macOS handles the notch area of full-screen apps itself.
- When the menu bar is set to hide automatically, the bar covers only the notch-height strip
  at the top of the screen.
- Rounded corners sit above most windows, so a few points of content at the very corners
  are hidden.
- The app is signed ad hoc, not notarized: on first launch macOS may ask you to confirm
  opening it.

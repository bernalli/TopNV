# topNV

![topNV](Assets/cover.png)

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

Click the menu-bar icon to open the native menu:

- **About topNV**: the standard About panel with the app icon, version, build, copyright
  and a link to the repository.
- **Hide Notch**: black menu bar on notched displays (default on).
- **Round Corners**: rounded screen corners (default on).
- **Corner Radius**: choose 5, 10, 15, 20, 25 or 30 points (default 15). Other values
  appear as a selected **Custom** row, such as **Custom (13 pt)**.
- **Corners on All Displays**: round corners on external displays too (default: built-in
  display only).
- **Settings…** (Command-comma): open the Settings window.
- **Help**: open this README, release notes, a new GitHub issue or the source repository.
- **Quit topNV** (Command-Q).

The Settings window has two sections:

- **Display**: Hide Notch, Round Corners, a **Corner Radius** slider from 0 to 30 points
  in one-point steps, and Corners on All Displays. Changes apply live and stay in sync
  with the menu. Corner Radius and Corners on All Displays remain visible but disabled
  in both places while Round Corners is off.
- **General**: **Launch at Login** registers the app as a login item. If macOS asks for
  approval, allow it in System Settings > General > Login Items; approval requests and
  registration errors appear here. Turn off **Show in Menu Bar** to hide the icon while
  topNV keeps running. Open topNV again to bring the icon back.

## Download

Download `topNV-<version>.dmg` from the
[latest release](https://github.com/bernalli/topNV/releases/latest), open it and drag
**topNV** into **Applications**.

topNV is signed ad hoc, not notarized. The first time, right-click the app in Applications
and choose **Open**, then confirm (or allow it in System Settings > Privacy & Security).

Requires macOS 14 or later.

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

To pack the app into a disk image, run `scripts/make-dmg.sh` after `scripts/bundle.sh`; it
writes `build/topNV.dmg`.

## Publish a release

The `Release` workflow (`.github/workflows/release.yml`) builds a universal app, packs it into
a DMG and publishes it as a GitHub Release. Start it in one of two ways:

- push a tag such as `v1.0.0`, or
- in the Actions tab, open **Release**, click **Run workflow** and enter a version such as
  `1.0.0`; the workflow creates the tag `v1.0.0`.

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

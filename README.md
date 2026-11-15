<div align="center">
  <img src="Assets/cover.png" alt="TopNV" width="800">
  <h1>TopNV</h1>
  <p>Blend the MacBook notch into a black menu bar and give your display rounded corners.</p>
  <p>
    <a href="https://github.com/bernalli/TopNV/releases/latest"><img src="https://img.shields.io/github/v/release/bernalli/TopNV?label=release" alt="Latest release"></a>
    <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14 or later">
  </p>
</div>

## Download

**[Download the latest release](https://github.com/bernalli/TopNV/releases/latest)** · macOS 14 or later

Open `TopNV-<version>.dmg` and drag **TopNV** into **Applications**.

From version 1.2.0, TopNV is signed with Developer ID and notarized by Apple.

## Features

- Hide the notch against a black menu-bar strip on notched displays.
- Round the corners of the built-in display with a fixed 15-point radius, or enable corners on all displays.
- Keep your wallpaper untouched, including dynamic and animated wallpapers.
- Launch at login and optionally hide the menu-bar icon while the app keeps running.

TopNV has no Dock icon. No Screen Recording or Accessibility permission is required.
Hide Notch and Round Corners start enabled; corners are rounded on the built-in display.
Your choices are saved automatically.

## Menu

Click the menu-bar icon to see the current configuration and change it directly.

| Item | What it does |
| --- | --- |
| Hide Notch | Turn the black menu-bar strip on or off. |
| Round Corners | Turn corner overlays on or off. |
| Details | Show the selected display scope and system requirements; open the source, release notes or issue tracker. |
| Options | Set **Corners on All Displays**, **Launch at Login**, **Automatically Check for Updates** and **Hide Menu Bar Icon**. |
| Check for Updates… | Check manually, including when automatic checks are off. |
| Version / About TopNV | Show the installed version and the About window with a GitHub icon and a Buy Me a Coffee button. |
| Quit TopNV · ⌘Q | Stop the app and remove its overlays. |

Corners on All Displays is disabled while Round Corners is off.
If Launch at Login needs approval, Options tells you to allow it in
**System Settings > General > Login Items**; registration errors appear there too.

To restore a hidden menu-bar icon, **open TopNV again from Applications**.

## Updates

Automatic checks start **off**. On the first opening with update support, TopNV asks
once whether to check automatically. Choosing **Don't Check**, pressing Esc or
closing the question leaves automatic checks off. Change the choice later in
**Options > Automatic Updates**. No check runs before that answer.

Use **Check for Updates…** for a manual check. A compact window in the style of a system
alert shows the new version; choose **Install and Relaunch** to install it, or **Later**.
Installation never happens silently. When a scheduled check finds an update, the same
window appears without activating TopNV or taking focus while you work elsewhere.

Version **1.0.0 has no updater**: download the new DMG and replace TopNV in Applications
manually once. The new updater preserves the same preference domain and login identity.

The DMG archives have Ed25519 signatures checked before extraction. The appcast feed
itself is not signed; its metadata and release notes are outside the archive signature.

## How it works

TopNV places a black, click-through window behind the menu bar on each notched display.
The system menu bar draws above it, keeping its items readable and clickable.
It neither reads nor changes the wallpaper.

Four small click-through overlays create the rounded corners. They sit above the Dock
and ordinary windows, below pop-up menus. The overlays update when settings, displays
or Spaces change, and after wake from sleep.

## Limitations

- The black menu-bar strip applies only to displays with a notch. Other displays keep
  their normal menu bar.
- The desktop-level black strip is covered in full-screen apps; macOS handles their
  notch area itself.
- With an automatically hidden menu bar, the black strip covers only the notch-height
  area at the top of the screen.
- Rounded corners hide a few points of content at the very corners of the display.

## Build from source

Install Xcode 16 or later with its macOS SDK and command-line tools selected, then run:

```sh
git clone https://github.com/bernalli/TopNV.git
cd TopNV
scripts/bundle.sh
open build/TopNV.app
```

The script builds the release executable, assembles `build/TopNV.app` and signs it locally,
without a certificate. Set `TOPNV_SIGN_IDENTITY` to a Developer ID Application identity to
sign every component with the hardened runtime instead.
Move the app to Applications to keep it installed. To bundle an existing executable,
set `TOPNV_EXECUTABLE` to its path when running the script. `Sparkle.framework` must
be beside that executable. The bundle requires the public verification key in
`Assets/SparklePublicEDKey.txt` and both license notices; missing or altered inputs
stop packaging before the previous app is removed.

Run the tests with:

```sh
swift test
```

## Releases

[Release notes and downloads](https://github.com/bernalli/TopNV/releases) are on GitHub.
Releases are made on a Mac from a clean `main` with `scripts/release-local.sh <version> <build>`.
It builds a universal app for Apple silicon and Intel, signs it with Developer ID,
notarizes and staples the DMG, signs the appcast with the EdDSA key in the Keychain and
publishes a versioned DMG. Releases are verified in draft before publication. The hosted
release workflow no longer runs on tags and stops at the signature check. The public
`update-proof` prerelease is reserved for testing and must not be installed by users.

For a local disk image, run `scripts/make-dmg.sh` after `scripts/bundle.sh`;
the result is `build/TopNV.dmg`.

## License

TopNV is released under the [MIT License](LICENSE). Sparkle and its bundled
components retain their complete [license notices](Licenses/Sparkle.txt), also
included alongside the TopNV license inside the app.

## Support

If TopNV is useful to you, you can [buy me a coffee](https://github.com/sponsors/bernalli).

## Author

Created by Samuele Martinalli.

Copyright (c) 2026 Samuele Martinalli. Released under the [MIT License](LICENSE).

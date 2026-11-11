# IconFinder

A macOS app that finds application icons on your Mac and exports them as PNG files. It scans `.app` bundles, `.pkg` installers and `.dmg` disk images.

IconFinder is a SwiftUI version of the `extract_mac_app_icons.sh` script from [Jamf-Scripts](https://github.com/RussCollis/Jamf-Scripts). It's useful for collecting icons for Jamf Pro Self Service, policies and other admin tooling.

## Features

- **Default search locations** (same as the original script):
  - `/Applications`
  - `/System/Applications`
  - `/Library`
  - `/System/Library`
  - `~/Downloads`
- **Custom search locations.** Add as many extra folders as you like. Any location can be switched on or off.
- **Choose the output folder.** Defaults to `~/Desktop/MacAppIcons`.
- **Three sources:**
  - `.app` bundles: the icon named by `CFBundleIconFile`
  - `.pkg` installers: every `.icns` file in the fully expanded package
  - `.dmg` disk images: mounted read-only and hidden from Finder; extracts each app's icon plus any loose `.icns` files
- **Skips duplicates.** Icons that already exist in the output folder are left alone.
- **Live log and summary.** Counts of extracted, skipped and missing icons, plus a `_YYYY-MM-DD_icon_extraction_summary.txt` report written to the output folder.
- **Settings are remembered** between launches.

## Output layout

| Source | Output path |
|---|---|
| App bundle | `<output>/<App Name>/<App Name>.png` |
| Package | `<output>/<Package Name>/<icon name>.png` |
| App inside a disk image | `<output>/<DMG Name>_<App Name>/<App Name>.png` |
| Loose `.icns` in a disk image | `<output>/<DMG Name>/<icon name>.png` |

Each PNG is the largest image in the source `.icns` file. Names keep only letters, numbers, spaces, `_` and `-`.

## Requirements

- macOS 27.2 or later
- A Mac with Apple silicon

## Installation

Run `IconFinder-1.1.pkg`. It installs `IconFinder.app` into `/Applications`.

> **Note:** current builds are ad-hoc signed and not notarized. On Macs other than the one that built them, Gatekeeper will block the app. Either deploy through Jamf Pro / MDM, or right-click the app, choose **Open**, and approve it in **System Settings → Privacy & Security**.

## Building from source

Open `Icon Finder.xcodeproj` in Xcode and run the **Icon Finder** scheme.

To build the app and the installer package from the command line:

```bash
./scripts/build_pkg.sh
```

This produces:

- `dist/IconFinder.app`
- `dist/IconFinder-<version>.pkg`

The installer shows the MIT License, requires the macOS version in the app's `LSMinimumSystemVersion`, and always installs to `/Applications`.

## Why the App Sandbox is off

IconFinder has to read system locations such as `/System/Library` and run `/usr/sbin/pkgutil` and `/usr/bin/hdiutil`. The App Sandbox blocks both, so it's turned off. That means the app can't be distributed through the Mac App Store.

## Known limitations

- Apps that store their icon only in an asset catalog (`CFBundleIconName` / `Assets.car`), with no `.icns` file, are reported as missing.
- Disk images that need you to accept a license agreement, or that are encrypted, can't be mounted, so they're skipped.
- Expanding large `.pkg` files fully can take a while.

## Author

Russell Collis

## License

Released under the [MIT License](LICENSE). Copyright © 2026 Russell Collis.

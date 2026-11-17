# WallVue

Live wallpapers for your desktop. Free and open source (MIT). No trial, no
paid tier, no account.

## Status

Early development. This is what works today on macOS:

- Video wallpapers on the desktop of every display, or a different one per display
- Still-image wallpapers
- Library with favourites, categories, search and your own imported files
- Day schedule ("at each time, it changes") and Shuffle
- Menu bar panel with controls and the app's own CPU and memory use
- Pauses itself when the desktop is covered, on display sleep, on lock, in Low
  Power Mode, when the Mac is hot, and optionally on battery
- Readability controls: dim and blur the wallpaper behind your icons
- Live Lock Screen and screen saver on macOS 26 (off by default; Settings → Lock Screen)
- Otherwise the Lock Screen shows a matching still frame
- Keeps playing after you quit: Quit hides WallVue and leaves the wallpaper
  running; Quit Completely (⌥⌘Q) stops it
- Loop maker: trims a video and blends its end into its beginning so the
  repeat can't be seen
- Pauses during video calls, and optionally while the microphone is in use or
  the screen is shared or recorded
- Shortcuts that work in every app (⌃⌥⌘P play or pause, ⌃⌥⌘M sound)
- Daily update check against this repository's releases (can be turned off)

Not built yet:

- Online catalogue
- A system wallpaper extension, so macOS plays the desktop with no part of
  WallVue left running
- Windows and Linux

## Requirements

macOS 14 or later. Live Lock Screen and screen saver need macOS 26.

## Install (macOS)

There is no release yet. When there is, download `WallVue-<version>.dmg` from
the Releases page, drag WallVue to Applications and open it.

WallVue is built without a paid Apple developer certificate, so the first time
macOS says it can't check the app. Open System Settings → Privacy & Security,
scroll down and click **Open Anyway** next to WallVue. You only do this once.

## Build (macOS)

```bash
cd apps/macos
swift test                      # unit tests for the core
./Scripts/build-app.sh release  # produces build/WallVue.app
open build/WallVue.app
./Scripts/package.sh            # Apple silicon + Intel build/WallVue-<version>.dmg
```

How a release is made: [docs/releasing.md](docs/releasing.md).

## Layout

```
apps/macos/     the macOS app (Swift, SwiftUI, AVFoundation)
apps/desktop/   Windows + Linux app (not started)
catalogue/      the list of downloadable wallpapers (no video files)
docs/           file formats and notes
```

Your library lives in `~/Library/Application Support/WallVue/`.

## Licence

MIT. See [LICENSE](LICENSE).

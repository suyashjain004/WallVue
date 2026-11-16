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

Not built yet:

- Desktop that keeps moving after WallVue quits (a system wallpaper extension)
- Online catalogue
- Loop maker, call and screen-share awareness, shortcuts that work in every app
- Windows and Linux

## Requirements

macOS 14 or later. Live Lock Screen and screen saver need macOS 26.

## Build (macOS)

```bash
cd apps/macos
swift test                      # unit tests for the core
./Scripts/build-app.sh release  # produces build/WallVue.app
open build/WallVue.app
```

The build is signed ad hoc, so the first launch of a copy you downloaded needs
System Settings → Privacy & Security → Open Anyway.

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

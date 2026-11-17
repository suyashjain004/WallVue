# WallVue

Live wallpapers for your desktop. Free and open source (GPL-3.0). No trial, no
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
- A built-in catalogue of free wallpapers: browse them in Explore, download the
  ones you want, and new ones appear without an app update

Not built yet:

- A system wallpaper extension, so macOS plays the desktop with no part of
  WallVue left running
- Windows and Linux

## Requirements

macOS 14 or later. Live Lock Screen and screen saver need macOS 26.

## Install (macOS)

Download `WallVue-<version>.dmg` from the
[Releases page](https://github.com/suyashjain004/WallVue/releases) (the newest
release whose name starts with "WallVue"), drag WallVue to Applications and
open it.

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

Copyright (c) 2026 Prasham and the WallVue contributors.

WallVue is free software: you can redistribute it and/or modify it under the
terms of the GNU General Public License, version 3, as published by the Free
Software Foundation. It is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY. See [LICENSE](LICENSE) for the full terms. In short: you
may use, study, change and share it, and if you distribute a changed version
you must publish its source under the same licence.

The wallpapers in the catalogue are not part of the software and have their
own licence, CC BY-NC-ND 4.0. See [catalogue/LICENSE.md](catalogue/LICENSE.md).

Third-party credits are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

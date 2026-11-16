# Data formats

All files are JSON in `~/Library/Application Support/WallVue/` on macOS. Other
platforms use the same formats in their own data folder.

| File | Contents |
|---|---|
| `library.json` | Array of wallpapers: id, title, fileName, kind (`video`/`still`), origin (`imported`/`catalogue`), category, width, height, duration, frameRate, hasAudio, fileSize, isFavorite, dateAdded, lastPlayed, playCount |
| `state.json` | What is playing where: defaultWallpaperID, per-display assignments, and the pictures to restore on Stop |
| `schedule.json` | Day schedule: array of slots with `minutes` after midnight and an optional `wallpaperID` |
| `Media/` | Wallpaper files, named `<id>.<ext>` |
| `Thumbnails/` | JPEG previews, `<id>.jpg` |
| `Stills/` | First frames of videos, used as the system wallpaper |

The catalogue format is described in `catalogue/README.md`.

# Catalogue

`index.json` lists the wallpapers WallVue can download.

- **The list and the thumbnails live here**, in `index.json` and `thumbnails/`.
- **The videos do not.** They are attached to releases of this repository
  named `wallpapers-1`, `wallpapers-2`, and so on, and the list points at them.
  (Those names are deliberately not version numbers, so the app's update check
  ignores them. See `docs/releasing.md`.)

Each entry:

```json
{
  "id": "aurora-veil",
  "title": "Aurora Veil",
  "kind": "video",
  "category": "Nature",
  "width": 3840, "height": 2160, "duration": 16, "frameRate": 30,
  "size": 15728640,
  "license": "CC-BY-NC-ND-4.0",
  "credit": "WallVue",
  "thumbnail": "https://raw.githubusercontent.com/suyashjain004/WallVue/main/catalogue/thumbnails/aurora-veil.jpg",
  "files": ["https://github.com/suyashjain004/WallVue/releases/download/wallpapers-1/aurora-veil.mp4"]
}
```

`files` is tried in order, so a second host can be added, or a host replaced,
without an app update.

## What may go in

Every entry must carry a licence that allows redistribution, and a credit.
Clips from films, games or TV, clips of real people, and anything copied from
another wallpaper app or site are not accepted. "Free to watch" is not a
licence: the original creator has to have stated one.

## The first set

The wallpapers in `wallpapers-1` are WallVue's own: original loops made for
this project, with no footage, photos or other people's artwork in them. They
are licensed CC BY-NC-ND 4.0 (use and share unchanged, with credit, not
commercially). See [LICENSE.md](LICENSE.md).

`source` is an optional field for entries that have a public original to
point to.

## Adding a wallpaper

```bash
python3 tools/add_wallpaper.py clip.mp4 --title "Misty Forest" --category Nature \
    --credit "Jane Doe" --license CC0-1.0 --source https://example.com/original
git add catalogue && git commit -m "Add Misty Forest to the catalogue" && git push
```

The command makes the thumbnail (960×540 JPEG), attaches the video to the
newest `wallpapers-N` release and adds the entry to `index.json`. People see
the wallpaper the next time the app refreshes its list; no app update is
needed. Start a new release (`--release wallpapers-2`) when one reaches 1,000
files.

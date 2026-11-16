# Catalogue

`index.json` lists the wallpapers WallVue can download. Only the list lives
here; video files and thumbnails are hosted elsewhere and referenced by URL.

Each entry:

```json
{
  "id": "misty-forest",
  "title": "Misty Forest",
  "kind": "video",
  "category": "Nature",
  "width": 3840, "height": 2160, "duration": 30, "frameRate": 30,
  "size": 52428800,
  "license": "CC0-1.0",
  "credit": "Jane Doe",
  "source": "https://example.com/original",
  "thumbnail": "https://example.com/thumbs/misty-forest.jpg",
  "files": ["https://primary.example.com/misty-forest.mov",
            "https://mirror.example.com/misty-forest.mov"]
}
```

`files` is tried in order, so hosts can be added or replaced without an app
update. Every entry must carry a licence that allows redistribution, and a
credit. Clips from films, games or TV, and clips of real people, are not
accepted.

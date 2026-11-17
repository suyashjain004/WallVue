#!/usr/bin/env python3
"""Adds one wallpaper to the catalogue.

    python3 add_wallpaper.py clip.mp4 --title "Misty Forest" --category Nature \\
        --credit "Jane Doe" --license CC0-1.0 --source https://example.com/original

It makes the thumbnail, attaches the video to the wallpapers release on
GitHub and adds the entry to index.json. With --publish it also commits and
pushes the catalogue folder, and then every copy of the app shows the new
wallpaper the next time it refreshes its list. Without --publish, commit and
push the catalogue folder yourself.

--category may be one of the built-in categories or a new name. A new
category gets its own filter in WallVue 0.1.1 and later; older copies list
its wallpapers under All and find them by search.

Only add videos you are allowed to redistribute. --license must name the
licence the original creator gave, and --credit must name them.

Needs ffmpeg, and gh (signed in) unless --no-upload is given.
"""
import argparse
import datetime
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = "suyashjain004/WallVue"
CATEGORIES = ["Nature", "Space", "Abstract", "City", "Ocean", "Minimal", "Dark", "Others"]
CATALOGUE = Path(__file__).resolve().parent.parent


def run(*command):
    return subprocess.run(command, check=True, capture_output=True, text=True).stdout


def main():
    parser = argparse.ArgumentParser(description="Add one wallpaper to the catalogue.")
    parser.add_argument("video", type=Path)
    parser.add_argument("--title", required=True)
    parser.add_argument("--category", required=True, help="one of " + ", ".join(CATEGORIES) + ", or a new name")
    parser.add_argument("--credit", required=True, help="who made it")
    parser.add_argument("--license", required=True, help="the licence it was published under, e.g. CC0-1.0 or CC-BY-4.0")
    parser.add_argument("--source", help="link to the original")
    parser.add_argument("--release", default="wallpapers-1", help="release that holds the video (default: wallpapers-1)")
    parser.add_argument("--no-upload", action="store_true", help="skip the upload (attach the file yourself)")
    parser.add_argument("--publish", action="store_true", help="also commit and push the catalogue folder")
    args = parser.parse_args()

    # Use the spelling already in use, so "ocean" and "Ocean" stay one category.
    wanted = " ".join(args.category.split())
    if not wanted or len(wanted) > 24:
        sys.exit("A category name needs 1 to 24 characters")

    if not args.video.is_file():
        sys.exit(f"{args.video} is not a file")
    if re.fullmatch(r"v?\d+(\.\d+)*", args.release):
        sys.exit("A wallpapers release must not be named like a version number; the app would take it for an update.")

    index_file = CATALOGUE / "index.json"
    index = json.loads(index_file.read_text())
    known = CATEGORIES + [entry["category"] for entry in index["wallpapers"]]
    category = next((name for name in known if name.lower() == wanted.lower()), wanted)
    is_new_category = category.lower() not in (name.lower() for name in known)
    slug = re.sub(r"[^a-z0-9]+", "-", args.title.lower()).strip("-")
    if not slug:
        sys.exit("The title needs at least one letter or digit")
    if any(entry["id"] == slug for entry in index["wallpapers"]):
        sys.exit(f"The catalogue already has a wallpaper with the id {slug}")

    probe = json.loads(run("ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                           "stream=width,height,r_frame_rate:format=duration", "-of", "json", str(args.video)))
    stream = probe["streams"][0]
    duration = float(probe["format"]["duration"])
    rate_top, _, rate_bottom = stream["r_frame_rate"].partition("/")
    frame_rate = round(float(rate_top) / float(rate_bottom or 1), 2)

    extension = args.video.suffix.lower()
    if extension not in (".mp4", ".mov", ".m4v"):
        sys.exit("The video must be an .mp4, .mov or .m4v file")
    name = f"{slug}{extension}"

    thumbnail = CATALOGUE / "thumbnails" / f"{slug}.jpg"
    thumbnail.parent.mkdir(exist_ok=True)
    run("ffmpeg", "-nostdin", "-v", "error", "-y", "-ss", f"{duration * 0.3:.2f}", "-i", str(args.video), "-frames:v", "1",
        "-vf", "scale=960:540:force_original_aspect_ratio=increase,crop=960:540", "-q:v", "3", str(thumbnail))

    if not args.no_upload:
        with tempfile.TemporaryDirectory() as folder:
            staged = Path(folder) / name
            shutil.copyfile(args.video, staged)
            exists = subprocess.run(["gh", "release", "view", args.release, "--repo", REPO], capture_output=True).returncode == 0
            if not exists:
                run("gh", "release", "create", args.release, "--repo", REPO, "--title", args.release.replace("-", " ").title(),
                    "--notes", "Wallpaper files for the WallVue catalogue. Not an app release.", "--latest=false")
            run("gh", "release", "upload", args.release, str(staged), "--repo", REPO, "--clobber")

    entry = {
        "id": slug, "title": args.title, "kind": "video", "category": category,
        "width": stream["width"], "height": stream["height"],
        "duration": round(duration, 2), "frameRate": frame_rate,
        "size": args.video.stat().st_size,
        "license": args.license, "credit": args.credit,
        "thumbnail": f"https://raw.githubusercontent.com/{REPO}/main/catalogue/thumbnails/{slug}.jpg",
        "files": [f"https://github.com/{REPO}/releases/download/{args.release}/{name}"],
    }
    if args.source:
        entry["source"] = args.source
    index["wallpapers"].append(entry)
    index["updated"] = datetime.date.today().isoformat()
    index_file.write_text(json.dumps(index, indent=2) + "\n")

    print(f"Added {args.title} ({slug}) to {category}.")
    if is_new_category:
        print(f"{category} is a new category. WallVue 0.1.1 and later show a filter for it; older copies list it under All.")
    if args.no_upload:
        print(f"Attach the video to the {args.release} release as {name}.")
    message = f"Add {args.title} to the catalogue"
    if args.publish:
        repo = CATALOGUE.parent
        run("git", "-C", str(repo), "add", "catalogue")
        run("git", "-C", str(repo), "commit", "-m", message)
        run("git", "-C", str(repo), "push")
        print("Published. Copies of the app show it the next time they refresh their list.")
    else:
        print(f'Now: git add catalogue && git commit -m "{message}" && git push')


if __name__ == "__main__":
    main()

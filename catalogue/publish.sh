#!/bin/bash
# One command to put a wallpaper in front of everyone who has WallVue:
# makes the thumbnail, uploads the video, adds it to the list, commits and
# pushes.
#
#   catalogue/publish.sh <video> "<Title>" <Category> "<Creator>" <Licence> [link to the original]
#
#   catalogue/publish.sh ~/Downloads/forest.mp4 "Misty Forest" Nature "Jane Doe" CC0-1.0 https://example.com/forest
#
# Category: Nature, Space, Abstract, City, Ocean, Minimal, Dark, Others, or a new name.
# Creator and Licence must be the real ones: who made the video, and the
# licence they published it under. It has to allow redistribution.
#
# Needs ffmpeg and gh (signed in to GitHub).
set -euo pipefail
if [ "$#" -lt 5 ]; then
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
fi
cd "$(dirname "$0")/.."
git pull --ff-only --quiet
SOURCE=()
if [ -n "${6:-}" ]; then SOURCE=(--source "$6"); fi
python3 catalogue/tools/add_wallpaper.py "$1" --title "$2" --category "$3" --credit "$4" --license "$5" \
    ${SOURCE[@]+"${SOURCE[@]}"} --publish

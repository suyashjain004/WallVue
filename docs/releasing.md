# Releasing WallVue for macOS

The version lives in one place: `apps/macos/VERSION`. The build number is the
number of commits, so it always goes up.

## Steps

1. Change `apps/macos/VERSION` (for example `0.2.0`) and commit.
2. Tag that commit and push the tag:

   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```

3. The "Release (macOS)" workflow runs the tests, builds the app for Apple
   silicon and Intel, packs `WallVue-0.2.0.dmg` and publishes a release named
   after the tag with the disk image attached. It refuses to run if the tag
   and the VERSION file disagree.

To make the disk image on your own Mac instead, run
`apps/macos/Scripts/package.sh`. It prints the file's SHA-256.

The workflow only runs for version tags or when started by hand from the
Actions tab, never on ordinary pushes.

## How the app finds updates

Once a day (and from Settings → About) WallVue asks GitHub for this
repository's releases and looks for the highest tag that is a plain version
number: `v0.2.0`, `1.4`, and so on. Drafts and pre-releases are skipped.

Releases that hold wallpaper files must therefore **not** use a version number
as their tag. Name them `wallpapers-1`, `wallpapers-2`, and the app ignores
them when checking for updates.

There is no automatic install. The app shows that a newer version exists and
opens its release page; the person downloads the disk image and replaces the
copy in Applications.

## Signing

Builds are signed ad hoc (no Apple Developer account). macOS asks whoever
downloads the app to approve it once in System Settings → Privacy & Security →
Open Anyway. The disk image carries a "Read Me First" file that explains this.

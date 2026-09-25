# Photos Clone

A native macOS app for browsing the copy of iCloud Photos you get from
[privacy.apple.com](https://privacy.apple.com) ("Request a copy of your data" → iCloud Photos),
laid out like Apple's Photos app.

## What Apple gives you

The export arrives as `iCloud Photos Part 1 of N.zip` … `Part N of N.zip`. Unzipped:

| Path | Contents |
|---|---|
| `Part X/Photos/` | The originals (HEIC, JPG, PNG, MOV, MP4…) plus `Photo Details.csv`, `Photo Details-1.csv`, … |
| `Photo Details*.csv` | `imgName,fileChecksum,favorite,hidden,deleted,originalCreationDate,viewCount,importDate`. Dates look like `"Monday January 2,2023 4:05 PM GMT"` |
| `Part X/Recently Deleted/` | Media still in Recently Deleted |
| `Part 1/Albums/<name>.csv` | One CSV per album, header `Images`. `Hidden.csv` and `Favorites.csv` use `imgName` |
| `Part 1/Memories/<name>.csv` | One CSV per memory, header `imageName` |
| `Part 1/iCloud Shared Albums.zip` | `My Albums/<album>/` with the media and an `AlbumInfo.json` |
| `icloudUsageData*.zip` | Shared-album activity log (not shown) |

Some details that matter:

- **File names are not unique.** The same `IMG_0100.MOV` can appear in two parts as two different
  videos. Each file is matched to the `Photo Details` CSV in its own folder first.
- **Live Photos** are two files (`IMG_1234.HEIC` and `IMG_1234.MOV`). They are shown as one item
  when both halves sit in the same folder and were created within two minutes of each other.
- Albums and memories only list file names, so an album entry whose name matches several files
  shows all of them.
- EXIF (camera, lens, GPS, capture time) is not in the CSVs. The app reads it from the files in the
  background and caches it in `~/Library/Application Support/PhotosClone/`.

## Features

- Library by **Years / Months / All Photos**, Favorites, **Map**, **Memories** (with a slideshow),
  Shared Albums, all your albums, and a view for each export part
- Media types: Videos, Live Photos (hover **LIVE** to play), Screenshots, Screen Recordings, Animated
- **Hidden** and **Recently Deleted** are locked behind Touch ID, Apple Watch or your password, like in Photos, and relock when the Mac sleeps or locks
- **Duplicates**: items that share an iCloud checksum
- Viewer: zoom with pinch or double-click, ← → to move, filmstrip, video playback, Info panel (⌘I)
  with camera settings, a map and the iCloud metadata
- Search by file name, album, month or year, camera, or words like "video" and "favorite"
- Select items (⌘-click or ⇧-click) and **Export** them to copy the originals out, Live Photo halves
  included, with the capture date set on each file
- **Reads straight from the zips.** You don't need to unzip anything. Photos are unpacked in memory
  as you view them. Videos are unpacked into a cache on the Mac's internal SSD only when played; the
  cache is capped at 10% of free space and removes the oldest first. The external drive is only read.
- **Free Up Space** (File menu) checks that every file in the unzipped folders is also inside the
  zips (by name and size, content checksums for renamed copies, and a byte-for-byte sample), and
  saves all thumbnails ahead of time. It then tells you which folders are safe to delete. It never
  deletes anything itself.

Nothing is modified inside the export folder.

## Build

```bash
./scripts/build-app.sh --install
```

Builds `dist/Photos Clone.app` and copies it to `~/Applications`. This works with just the Command
Line Tools. To sign with your Apple Developer account, set
`SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"` first.

Command-line checks (no window):

- `PhotosClone --scan "/path/to/export" [--zips-only]` prints what the scanner finds
- `PhotosClone --storage-check "/path/to/export"` runs the Free Up Space check
- `PhotosClone --zip-test "/path/to/part.zip" [root]` lists a zip and compares entries with unzipped files

# Regain Your Data

Native macOS apps for **reading the copies of your data that Apple, Snapchat, Instagram and
WhatsApp let you download**, laid out the way the original apps show them. The exports arrive as
zip files full of CSVs, JSON, HTML and loose media; these apps turn them back into something you
can browse, straight from the zips, without uploading anything anywhere.

| App | Reads | Looks like |
|---|---|---|
| **Photos Clone** | iCloud Photos from [privacy.apple.com](https://privacy.apple.com) ("iCloud Photos Part 1 of N.zip") | Apple Photos: library, albums, memories, map, Hidden and Recently Deleted (Touch ID / Apple Watch lock), on-device search, dates fixed from the files |
| **Snapchat Clone** | Snapchat "My Data" (mydata~….zip) with Memories | Snapchat Memories: Snaps with Flashbacks, Stories, Chats with media and voice notes, and a passcode-locked My Eyes Only |
| **Instagram Clone** | Instagram "Download your information" in **HTML** format (instagram-….zip) | Instagram Direct: accounts, inbox, requests, bubbles, reactions, photos, videos, voice notes, profile page |
| **WhatsApp Clone** | WhatsApp "Export Chat" with media (WhatsApp Chat - ….zip) | WhatsApp desktop: bubbles, ticks, wallpaper, stickers, GIFs, voice notes, documents |

Each app's folder under [`apps/`](apps) has a README describing the export format it reads.

## Download

Get the apps from the [latest release](../../releases/latest): **All-Apps.zip**, or any single app.
Unzip, move the app to Applications, then **right-click it and choose Open** the first time.
The apps aren't notarized yet, so macOS asks before opening an app downloaded from the internet.
If it refuses outright, run `xattr -dr com.apple.quarantine "/Applications/<App>.app"`.

Requires macOS 14 or later, on Apple silicon or Intel.

## Build from source

Needs the Xcode Command Line Tools (`xcode-select --install`); full Xcode is optional. With
Xcode's `actool`, the icons are also compiled as layered Liquid Glass icons that follow the
light, dark, clear and tinted styles.

```bash
./scripts/build-all.sh                 # every app, zipped into dist.noindex/
./scripts/build-all.sh WhatsAppClone   # just one
./scripts/build-all.sh --install       # also copy into /Applications
```

## Privacy

- Everything is read on your Mac. The apps have no accounts, analytics or uploads.
- The only network use is Apple Maps tiles in Photos Clone's map views.
- Your export is never modified. Photos Clone keeps your own edits (favorites, hidden, deleted)
  in a small file beside its caches.
- Thumbnails and parsed data are cached in `~/Library/Caches/<app>` and
  `~/Library/Application Support/<app>`; delete those folders to remove them.

## Not affiliated

These are independent tools for reading your own data. They are not made, endorsed or
supported by Apple, Snap Inc., Meta or WhatsApp. Product names are used only to say which export
each app reads, and the icons are original drawings.

## License

[MIT](LICENSE)

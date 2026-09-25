# Regain Your Data

Native macOS apps for **reading the copies of your data that Apple, Snapchat, Instagram,
WhatsApp and Amazon let you download**, laid out the way the original apps show them. The exports
arrive as zip files full of CSVs, JSON, HTML and loose media; these apps turn them back into
something you can browse, straight from the zips, without uploading anything anywhere.

**Regain Your Data** is the one app that holds them all: a switcher down the left side jumps
between Photos, Snapchat, Instagram, WhatsApp and Amazon, each in its own look, plus **Explorer**
for any other export (Google Takeout, Facebook, TikTok, Spotify…), which opens CSVs as
spreadsheets, JSON as a tree and HTML pages offline, and searches inside every file at once.
Each app is also available on its own.

| App | Reads | Looks like |
|---|---|---|
| **Photos Clone** | iCloud Photos from [privacy.apple.com](https://privacy.apple.com) ("iCloud Photos Part 1 of N.zip") | Apple Photos: library, albums, memories, map, Hidden and Recently Deleted (Touch ID / Apple Watch lock), on-device search, dates fixed from the files |
| **Snapchat Clone** | Snapchat "My Data" (mydata~….zip) with Memories | Snapchat Memories: Snaps with Flashbacks, Stories, Chats with media and voice notes, and a passcode-locked My Eyes Only |
| **Instagram Clone** | Instagram "Download your information" in **HTML** format (instagram-….zip) | Instagram Direct: accounts, inbox, requests, bubbles, reactions, photos, videos, voice notes, profile page |
| **WhatsApp Clone** | WhatsApp "Export Chat" with media (WhatsApp Chat - ….zip) | WhatsApp desktop: bubbles, ticks, wallpaper, stickers, GIFs, voice notes, documents |
| **Amazon Clone** | Amazon "Request Your Data" (Prime Video.zip, Your Orders.zip … with FileDescriptions.csv) | Amazon Your Orders with order cards and details, spending charts, Prime Video watch history, and every other file as a table |
| **Explorer** (in the hub) | Any export: a folder or a zip | Files grouped by zip and folder; CSV, JSON, HTML, text, pictures, video, audio and PDF previews; search inside all files |

Each app's folder under [`apps/`](apps) has a README describing the export format it reads.

## Download

Get the apps from the [latest release](../../releases/latest): **Regain-Your-Data.zip** (everything
in one app), **All-Apps.zip** (every app on its own), or any single app.
Unzip, move the app to Applications, then **right-click it and choose Open** the first time.
The apps aren't notarized yet, so macOS asks before opening an app downloaded from the internet.
If it refuses outright, run `xattr -dr com.apple.quarantine "/Applications/<App>.app"`.

Requires macOS 14 or later, on Apple silicon or Intel.

## Build from source

Needs the Xcode Command Line Tools (`xcode-select --install`); full Xcode is optional. With
Xcode's `actool`, the icons are also compiled as layered Liquid Glass icons that follow the
light, dark, clear and tinted styles.

```bash
./scripts/build-all.sh                 # the hub and every app, zipped into dist.noindex/
./scripts/build-all.sh RegainHub       # just the hub
./scripts/build-all.sh WhatsAppClone   # just one app
./scripts/build-all.sh --install       # also copy into /Applications
```

## How it fits together

```
apps/
  RegainHub/        Regain Your Data: the switcher, home page and Explorer
  PhotosClone/      PhotosKit    + the Photos Clone launcher
  SnapchatClone/    SnapchatKit  + the Snapchat Clone launcher
  InstagramClone/   InstagramKit + the Instagram Clone launcher
  WhatsAppClone/    WhatsAppKit  + the WhatsApp Clone launcher
  AmazonClone/      AmazonKit    + the Amazon Clone launcher
packages/
  RegainCore/       reading zips in place, CSV parsing, the file browser behind Explorer
```

Each app is a library ("kit") with a small public entry point (`PhotosModule`, `AmazonModule`…:
its root view, its Open command and its menu items) and a two-line launcher, so the same code
runs on its own and inside the hub. Settings are shared too, so both open the same export.

**Adding another company** (say TikTok): create `apps/TikTokClone` with a `TikTokKit` library
exposing a `TikTokModule`, add it to `apps/RegainHub/Package.swift`, and add a case to `Source`
in `apps/RegainHub/Sources/RegainHub/Hub.swift`. `RegainCore` already reads zips, CSVs and
file descriptions, and `DataBrowser` gives any module an "all files" view for free.

## Privacy

- Everything is read on your Mac. The apps have no accounts, analytics or uploads.
- The only network use is Apple Maps tiles in Photos Clone's map views.
- Your export is never modified. Photos Clone keeps your own edits (favorites, hidden, deleted)
  in a small file beside its caches.
- Thumbnails and parsed data are cached in `~/Library/Caches/<app>` and
  `~/Library/Application Support/<app>`; delete those folders to remove them.
- Explorer shows HTML pages with every internet request blocked. Files it copies out of a zip
  to preview (videos, PDFs) go to `~/Library/Caches/RegainYourData/Preview` and are removed when
  the app quits.
- Amazon Clone's "Buy it again" and product links open amazon.com in your browser; the app itself
  never contacts Amazon, so product photos are shown as plain boxes.

## Not affiliated

These are independent tools for reading your own data. They are not made, endorsed or
supported by Apple, Snap Inc., Meta, WhatsApp or Amazon. Product names are used only to say which export
each app reads, and the icons are original drawings.

## License

[MIT](LICENSE)

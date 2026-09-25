# Snapchat Clone

(Source folder and internal name: SnapVault.)

A native macOS app for browsing a Snapchat "Download My Data" export in the style of Snapchat
Memories: Snaps with Flashbacks, Stories, Chats, and a passcode-locked My Eyes Only.

## What Snapchat gives you

The export arrives as `mydata~<id>.zip`, `mydata~<id>-1.zip`, … (about 2 GB each). Inside:

| Path | Contents |
|---|---|
| `memories/YYYY-MM-DD_<UUID>-main.jpg\|mp4` | A saved snap. The day is a **UTC** day. |
| `memories/YYYY-MM-DD_<UUID>-overlay.png` | Its caption/sticker/drawing layer (same UUID), drawn over the media |
| `memories/memories.html` | A grid showing only the day of each item; no time, no location |
| `chat_media/YYYY-MM-DD_b~<id>.jpeg\|mp4\|png…` | Chat media. `<id>` appears in the `Media IDs` of a message in `json/chat_history.json`, which gives the conversation, sender and exact time. Audio-only `.mp4` files are voice notes. Some files are labelled `.unknown` and are identified by their first bytes. |
| `chat_media/YYYY-MM-DD_media~zip-<UUID>.ext` | Older saved snaps and Discover content. Their `overlay~`, `thumbnail~` and `metadata~` parts have different UUIDs, so they can't be matched back together. |
| `shared_story/<uuid>.mp4` | Shared-story posts. Their IDs don't match `shared_story.json`, so each video's own recorded date is used. |
| `json/chat_history.json` | Every saved message per conversation: sender, time (microseconds), type (TEXT, MEDIA, STICKER, SHARE, NOTE, LOCATION), text, media IDs. All messages in an export are marked saved. |
| `json/snap_history.json` | Snaps sent and received (no media) |
| `json/friends.json` | Usernames → display names |

My Eyes Only content is **not** included in exports. Snapchat Clone has its own My Eyes Only instead.

Photos carry no EXIF date or location. Videos record their creation time, which matches the
file name's day in about 98% of cases and is used to order them within the day.

## Features

- **Snaps**: every memory newest first under month headers, captions drawn in, video lengths.
  **Flashbacks** at the top show this day in earlier years (never from My Eyes Only).
- **Stories**: days with three or more snaps become story cards; they play like Snapchat
  stories with progress bars, photos for 5 seconds, videos to the end. Click the left third to
  go back and the rest to go forward; arrow keys and space work too.
- **Chats**: every conversation (not only ones with media), laid out like Snapchat's chat
  screen: sender names (ME in red, friends in blue) with the matching bar, day separators,
  photos, videos and voice notes inline, stickers, shared links and snaps sent/received. Media
  that wasn't saved isn't in the export and shows as a placeholder. Each chat also has a Media
  view. The search box filters the open conversation's text.
- **My Eyes Only**: move snaps in from the right-click menu or a selection. Opens with a 4-digit
  passcode (stored as a salted, stretched hash in the Keychain) or Touch ID / Apple Watch. Five
  wrong tries pause entry for 30 seconds; the Mac password resets a forgotten passcode. It locks
  when you leave the tab, the Mac sleeps or the screen locks. Items stay inside the export on
  disk; My Eyes Only hides and locks them in the app, it doesn't encrypt the export.
- **Export**: readable names (`Snap 2019-06-15 14.30.00.mp4`), correct file dates, and an option
  to burn captions and stickers into photos and videos.
- Reads the zips directly. Clips (all under 40 MB) are unpacked into memory for playback and
  thumbnails, so nothing is written to disk except small thumbnails in
  `~/Library/Caches/SnapVault`.

## Build

```bash
./scripts/build-app.sh --install
```

Command-line checks: `SnapVault --scan <folder>`, `SnapVault --check <folder>`,
`SnapVault --media-test <folder>`.

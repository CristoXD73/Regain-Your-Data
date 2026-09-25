# Instagram Clone

(Source folder and internal name: InstaVault.)

A native macOS app for reading Instagram "Download your information" exports (HTML format),
laid out like Instagram Direct. It reads the `instagram-<username>-<date>-<id>.zip` files
directly; unzipped copies are ignored.

## The export format

- `your_instagram_activity/messages/inbox/<name>_<id>/message_1.html, message_2.html…`: newest
  first. Each message is a `_a6-g` block: sender (`_a6-h`), content (`_a6-p`: text, a link, or
  `<img|video|audio src="your_instagram_activity/…">`, then reactions in `<ul class="_a6-q">`), and a
  minute-precision local time (`_a6-o`, "Jan 2, 2023 4:05 pm"). The first block on each page
  lists the participants and has no time. The chat's title is in `_a70e`.
- `photos/`, `videos/`, `audio/` sit next to each conversation's pages.
- `message_requests/` has the same layout. Many messages (shared posts, reels, story replies) come
  through empty; the app shows them as "not in the export".

## Features

- Switch between accounts; Messages and Requests folders; conversations sorted by latest message.
- Threads: your bubbles on the right in Instagram's blue-purple, others on the left in grey,
  names in group chats, time headers after an hour's gap, reactions, photos and videos inline
  (click for a full-window viewer with arrow keys), voice notes with a player, shared links as
  cards that open in your browser, and a per-chat grid of photos and videos.
- Search filters conversations by name or message text, and filters the open chat.
- The first launch parses each zip (a few seconds for tens of thousands of messages) and saves the result in
  `~/Library/Application Support/InstaVault`; later launches take a fraction of a second. Media
  plays from memory; only thumbnails are cached, in `~/Library/Caches/InstaVault`.

## Build

```bash
./scripts/build-app.sh --install
```

Checks: `InstaVault --check <folder>` (counts only), `InstaVault --media-test <folder>`.

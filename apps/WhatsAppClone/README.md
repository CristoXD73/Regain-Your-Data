# WhatsApp Clone

(Source folder and internal name: WhatsVault.)

Reads WhatsApp "Export Chat" zips (`WhatsApp Chat - <name>.zip`: `_chat.txt` plus attachments)
straight from the zip and shows them like WhatsApp desktop's dark theme: green bubbles for you,
day chips, doodle wallpaper, photos, stickers, GIFs, videos, voice notes, documents, deleted
messages, a Media and Docs view, and search in the chat list and inside a chat.

`_chat.txt` lines look like `[2023-01-02, 2:05:00 PM] Name: text`; a leading U+200E marks
attachments (`<attached: 00000012-PHOTO-….jpg>`) and system notices; lines without a date
continue the previous message. "You" is the participant who isn't the chat's name; for group
chats, pick yourself from the person menu in the chat header.

Build: `./scripts/build-app.sh --install`. Check: `WhatsVault --check <folder>` (counts only).

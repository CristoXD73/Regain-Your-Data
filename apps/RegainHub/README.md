# Regain Your Data (the hub)

One app holding all the others. The rail on the left switches between Home, Photos, Snapchat,
Instagram, WhatsApp, Amazon and Explorer; ⌘1…⌘7 do the same, ⌘O opens an export for the
current app, and the Library menu carries the current app's own commands.

- **Home** lists every app with the export it has open, and the companies still to come, with
  links to request your data from each.
- **Explorer** opens any export (folder or zip) with `RegainCore`'s `DataBrowser`: files grouped
  by zip and folder, previews for CSV, JSON, HTML (offline), text, pictures, video, audio and
  PDF, and search inside every file.

The apps are embedded as libraries (see the main README), so the hub and the standalone apps
share code and settings. Build: `./scripts/build-app.sh --install`.

Development: a debug build accepts `REGAIN_SOURCE=<home|photos|…>`, `REGAIN_EXPLORE=<folder>` and
`REGAIN_SNAPSHOT=<file.png>` (saves a picture of the window and quits), and Amazon Clone reads
`AMAZON_ROOT=<folder>` to open a sample export without changing the saved one.

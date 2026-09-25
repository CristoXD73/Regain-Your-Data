# Amazon Clone

(Source folder and internal name: AmazonVault; the code is in `AmazonKit`.)

Reads Amazon's "Request Your Data" download (amazon.com › Account › Request Your Information)
straight from its zips. Amazon delivers a request in parts, one zip per area, each with
"Your …" folders of CSVs, plus a `FileDescriptions.csv` explaining every file:

```
Prime Video.zip
  Your Prime Video Viewing Activity/Viewing History.csv     one row per playback
  Your Prime Video Viewing Activity/Search History.csv
  Your Prime Video Library & Purchases/Purchases and Rentals.csv
Your Orders.zip                                              (older: Retail.OrderHistory.1/…)
  Your Amazon Orders/Order History.csv                       one row per item shipped
FileDescriptions.csv
```

Put every part in one folder and open that folder; when more parts arrive, add them and open it
again.

- **Your Orders**: Amazon's order cards (placed, total, ship to, order number), items with
  quantity and price, "Buy it again" links, full order details, filter by year and search.
- **Spending**: totals, by year and by month, biggest purchases, things bought again and again.
- **Prime Video**: hours watched, most watched shows and films, watching by month, hour and day,
  day-by-day history (trailers and promos optional), searches, purchases and rentals. Episodes
  are titled `<episode>-<show> - Season N`; a split only counts as a show when several titles
  share it, so films with hyphens or colons stay whole.
- **All Data**: every file in the download as a table, with Amazon's own description of it.

Column names changed between versions ("Total Owed" → "Total Amount", "Quantity" → "Original
Quantity"), so columns are matched by any of their known names, ignoring case and punctuation.

Build: `./scripts/build-app.sh --install`. Check: `AmazonVault --check <folder>` (counts only).

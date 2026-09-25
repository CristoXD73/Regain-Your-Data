import Foundation

/// Picks the date an item sorts by, from iCloud's "originalCreationDate" (minute precision, and
/// for some items really the upload date) and the capture time stored in the file (seconds).
enum DateResolver {
    /// `camera` is the make/model recorded in the file, if any.
    static func resolve(_ a: Asset, fileDate: Date?, camera: String? = nil) -> Date {
        let csv = a.csvCreationDate
        guard let file = fileDate, isPlausible(file) else { return csv ?? a.importDate ?? .distantPast }
        // (Shared-album items carry their upload date from AlbumInfo.json in importDate.)
        guard let csv = csv ?? a.importDate else { return file }

        let diff = file.timeIntervalSince(csv)
        // Same moment: the file adds the seconds iCloud leaves out, which orders bursts correctly.
        if abs(diff) < 120 { return file }
        // Whole hours apart: a time-zone mismatch (screenshots store local time with no zone).
        // iCloud's time is the one with a zone; keep its minute and take the file's seconds.
        if abs(diff) < 26 * 3600 {
            let rem = diff.truncatingRemainder(dividingBy: 3600)
            if abs(rem) < 120 || abs(abs(rem) - 3600) < 120 {
                let seconds = Calendar(identifier: .gregorian).component(.second, from: file)
                return csv.addingTimeInterval(Double(seconds))
            }
        }
        // iCloud's date is just when the file was uploaded, and a camera recorded it well before
        // (videos from an old phone, photos copied from a camera): the camera is right. Images
        // saved from apps or the web keep the day they were saved, as Photos shows them.
        if diff < -86_400, camera != nil, let imported = a.importDate, abs(imported.timeIntervalSince(csv)) < 120 {
            return file
        }
        // Otherwise trust iCloud: it includes dates adjusted by hand in Photos.
        return csv
    }

    /// Cameras with an unset clock write 1970, 2000 or 2001; those dates are noise.
    private static func isPlausible(_ d: Date) -> Bool {
        let y = Calendar(identifier: .gregorian).component(.year, from: d)
        return y >= 2002 && d < Date().addingTimeInterval(86_400)
    }

    /// Chronological order, oldest first. Ties (same second) fall back to file-name order.
    static func ascending(_ x: Asset, _ y: Asset) -> Bool {
        if x.date != y.date { return x.date < y.date }
        let c = x.name.localizedStandardCompare(y.name)
        if c != .orderedSame { return c == .orderedAscending }
        return x.id < y.id
    }
}

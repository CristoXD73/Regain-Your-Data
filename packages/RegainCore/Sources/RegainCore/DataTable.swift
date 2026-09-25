import AppKit
import SwiftUI

/// A spreadsheet view for any CSV: columns come from the file, click a header to sort, ⌘C copies
/// the selected rows. Backed by NSTableView so files with hundreds of thousands of rows scroll
/// smoothly.
public struct DataTable: NSViewRepresentable {
    public let table: CSVTable
    public var filter: String

    public init(table: CSVTable, filter: String = "") {
        self.table = table
        self.filter = filter
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeNSView(context: Context) -> NSScrollView {
        let tv = CopyingTableView()
        tv.usesAlternatingRowBackgroundColors = true
        tv.allowsMultipleSelection = true
        tv.columnAutoresizingStyle = .noColumnAutoresizing
        tv.style = .fullWidth
        tv.rowHeight = 22
        tv.gridStyleMask = [.solidVerticalGridLineMask]
        tv.dataSource = context.coordinator
        tv.delegate = context.coordinator
        tv.coordinator = context.coordinator
        let sv = NSScrollView()
        sv.documentView = tv
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = true
        sv.autohidesScrollers = true
        return sv
    }

    public func updateNSView(_ sv: NSScrollView, context: Context) {
        guard let tv = sv.documentView as? NSTableView else { return }
        let c = context.coordinator
        let newTable = c.sourceID != table.id
        if newTable {
            c.header = table.header
            c.source = table.rows
            c.sourceID = table.id
            for col in tv.tableColumns { tv.removeTableColumn(col) }
            let sample = table.rows.prefix(200)
            for (i, h) in table.header.enumerated() {
                let col = NSTableColumn(identifier: .init("\(i)"))
                col.title = h
                col.headerToolTip = h
                col.sortDescriptorPrototype = NSSortDescriptor(key: "\(i)", ascending: true)
                let longest = max(h.count, sample.map { $0[safe: i].count }.max() ?? 0)
                col.width = CGFloat(min(420, max(70, longest * 7 + 16)))
                tv.addTableColumn(col)
            }
            tv.sortDescriptors = []
            c.filter = nil
        }
        if newTable || c.filter != filter {
            c.filter = filter
            c.apply(tv)
        }
    }

    public final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var header: [String] = []
        var source: [[String]] = []
        var sourceID: UUID?
        var rows: [[String]] = []
        var filter: String?

        func apply(_ tv: NSTableView) {
            let f = (filter ?? "").lowercased()
            rows = f.isEmpty ? source : source.filter { $0.contains { $0.lowercased().contains(f) } }
            sort(tv.sortDescriptors)
            tv.reloadData()
        }

        func sort(_ ds: [NSSortDescriptor]) {
            guard let d = ds.first, let key = d.key, let i = Int(key) else { return }
            // Numbers and dates sort as values when the whole column reads as them.
            let numeric = rows.prefix(500).allSatisfy { $0[safe: i].isEmpty || Double($0[safe: i]) != nil }
            rows.sort { a, b in
                let x = a[safe: i], y = b[safe: i]
                let less = numeric ? (Double(x) ?? -.infinity) < (Double(y) ?? -.infinity)
                                   : x.localizedStandardCompare(y) == .orderedAscending
                return d.ascending ? less : !less && x != y
            }
        }

        public func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        public func tableView(_ tv: NSTableView, sortDescriptorsDidChange old: [NSSortDescriptor]) {
            sort(tv.sortDescriptors)
            tv.reloadData()
        }

        public func tableView(_ tv: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
            guard let col, let i = Int(col.identifier.rawValue) else { return nil }
            let id = NSUserInterfaceItemIdentifier("cell")
            let cell = (tv.makeView(withIdentifier: id, owner: nil) as? NSTextField) ?? {
                let t = NSTextField(labelWithString: "")
                t.identifier = id
                t.lineBreakMode = .byTruncatingTail
                t.font = .systemFont(ofSize: 12)
                return t
            }()
            let v = rows[row][safe: i]
            cell.stringValue = v
            cell.toolTip = v.count > 40 ? v : nil
            return cell
        }

        func copy(_ tv: NSTableView) {
            let lines = tv.selectedRowIndexes.map { rows[$0].joined(separator: "\t") }
            guard !lines.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(([header.joined(separator: "\t")] + lines).joined(separator: "\n"), forType: .string)
        }
    }
}

final class CopyingTableView: NSTableView {
    weak var coordinator: DataTable.Coordinator?
    @objc func copy(_ sender: Any?) { coordinator?.copy(self) }
}

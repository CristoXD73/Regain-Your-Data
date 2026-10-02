import SwiftUI
import UniformTypeIdentifiers

// MARK: Draft return

/// The slips added up line by line, with your own entries, questions for the preparer and, when
/// refiling, what changes from the return as filed.
struct DraftView: View {
    @Environment(TaxStore.self) private var store
    @State private var newLine = ""
    @State private var newText = ""
    @State private var newAmount = ""

    var body: some View {
        let info = store.info
        let draft = store.draft()
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settings(info)

                if draft.isEmpty {
                    Label("Nothing to add up yet: import your slips in Documents.", systemImage: "tray").foregroundStyle(.secondary)
                }
                ForEach(ReturnLine.Section.allCases.filter { $0 != .totals }, id: \.self) { section in
                    let lines = draft.filter { $0.line.section == section }
                    if !lines.isEmpty {
                        GroupBox {
                            VStack(spacing: 0) {
                                ForEach(lines, id: \.line.id) { l in LineRow(line: l.line, total: l.total, parts: l.parts, country: info.country) }
                            }
                        } label: { Text(section.rawValue).font(.headline) }
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Amounts that aren't on a slip: RRSP contributions without a receipt, medical costs, rent, a correction…")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(info.entries) { e in
                            HStack {
                                Text(ReturnLine.lines(info.country).first { $0.id == e.line }?.code ?? e.line).font(.system(size: 11, design: .monospaced)).frame(width: 110, alignment: .leading)
                                Text(e.description)
                                Spacer()
                                Text(Amounts.parse(e.amount).map { Amounts.format($0, info.country) } ?? e.amount).monospacedDigit()
                                Button { var i = store.info; i.entries.removeAll { $0.id == e.id }; store.info = i } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                            }
                        }
                        HStack {
                            Picker("", selection: $newLine) {
                                Text("Line…").tag("")
                                ForEach(ReturnLine.lines(info.country).filter { $0.section != .totals }) { Text("\($0.code) – \($0.title)").tag($0.id) }
                            }
                            .labelsHidden().frame(width: 260)
                            TextField("What it is", text: $newText)
                            TextField("Amount", text: $newAmount).frame(width: 100)
                            Button("Add") {
                                var i = store.info
                                i.entries.append(ManualEntry(line: newLine, description: newText, amount: newAmount))
                                store.info = i
                                newText = ""; newAmount = ""
                            }
                            .disabled(newLine.isEmpty || Amounts.parse(newAmount) == nil)
                        }
                    }
                } label: { Text("Your own entries").font(.headline) }

                let missing = store.missingFromLastYear()
                if !missing.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(missing) { d in Label("\(d.spec.code) from \(d.payer.isEmpty ? d.fileName : d.payer)", systemImage: "questionmark.circle").foregroundStyle(.orange) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } label: { Text("You had these last year, but not this year").font(.headline) }
                }

                if info.amending { RefileView(draft: draft) }

                GroupBox {
                    TextEditor(text: Binding(get: { store.info.questions }, set: { var i = store.info; i.questions = $0; store.info = i }))
                        .font(.system(size: 13)).frame(minHeight: 90)
                } label: { Text("Questions and notes for your preparer").font(.headline) }

                Text("This is a draft to help you and your preparer. Totals here only add up your documents; limits, credits and tax are worked out by the forms and your preparer.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private func settings(_ info: TaxYearInfo) -> some View {
        HStack(spacing: 16) {
            Picker("Country", selection: Binding(get: { info.country }, set: { var i = store.info; i.country = $0; store.info = i })) {
                ForEach(Country.allCases) { Text("\($0.flag) \($0.name)").tag($0) }
            }
            .fixedSize()
            if info.country == .canada {
                Picker("Province", selection: Binding(get: { info.province }, set: { var i = store.info; i.province = $0; store.info = i })) {
                    ForEach(["AB", "BC", "MB", "NB", "NL", "NS", "NT", "NU", "ON", "PE", "QC", "SK", "YT"], id: \.self) { Text($0).tag($0) }
                }
                .fixedSize()
                TextField("Birth date (YYYY-MM-DD)", text: Binding(get: { info.birthDate }, set: { var i = store.info; i.birthDate = $0; store.info = i }))
                    .frame(width: 180).help("Only used on the T1, where age affects credits.")
            } else {
                TextField("State (e.g. NY)", text: Binding(get: { info.usState }, set: { var i = store.info; i.usState = String($0.prefix(2)).uppercased(); store.info = i }))
                    .frame(width: 110)
            }
            Spacer()
            Toggle("Refiling a return already filed", isOn: Binding(get: { info.amending }, set: { var i = store.info; i.amending = $0; store.info = i }))
        }
    }
}

private struct LineRow: View {
    let line: ReturnLine
    let total: Double
    let parts: [TaxStore.Contribution]
    let country: Country
    @State private var open = false
    @Environment(TaxStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button { open.toggle() } label: { Image(systemName: open ? "chevron.down" : "chevron.right").frame(width: 12) }.buttonStyle(.plain)
                Text(line.code).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                Text(line.title).fontWeight(.medium)
                if parts.contains(where: { !$0.reviewed }) {
                    Text("not all checked").font(.system(size: 9, weight: .bold)).foregroundStyle(.orange)
                        .padding(.horizontal, 5).padding(.vertical, 1).background(.orange.opacity(0.12), in: Capsule())
                }
                Spacer()
                Text(Amounts.format(total, country)).font(.system(size: 14, weight: .semibold)).monospacedDigit()
            }
            if let note = line.note { Text(note).font(.caption).foregroundStyle(.secondary).padding(.leading, 136) }
            if open {
                ForEach(parts) { p in
                    HStack {
                        Text(p.source).lineLimit(1)
                        Text(p.detail).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Text(Amounts.format(p.amount, country)).monospacedDigit()
                        if let id = p.documentID {
                            Button { store.selection = id; store.tab = .documents } label: { Image(systemName: "arrow.up.right.square") }.buttonStyle(.plain)
                        }
                    }
                    .font(.system(size: 12)).padding(.leading, 136)
                }
            }
        }
        .padding(.vertical, 6)
        Divider()
    }
}

private struct RefileView: View {
    @Environment(TaxStore.self) private var store
    let draft: [(line: ReturnLine, total: Double, parts: [TaxStore.Contribution])]

    var body: some View {
        let info = store.info
        let filed = store.asFiled()
        let totals = Dictionary(uniqueKeysWithValues: draft.map { ($0.line.id, $0.total) })
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(info.country == .canada
                     ? "Import the return you filed or its Notice of Assessment into this year; the lines it shows are compared with the draft. Your preparer files the change with ReFILE or a T1-ADJ."
                     : "Import the 1040 you filed into this year; its lines are compared with the draft. Your preparer files the change on Form 1040-X.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Why you're refiling (a missed slip, a corrected T4…)", text: Binding(get: { info.amendReason }, set: { var i = store.info; i.amendReason = $0; store.info = i }))
                let lines = ReturnLine.lines(info.country).filter { filed[$0.id] != nil || totals[$0.id] != nil }
                if filed.isEmpty {
                    Label("No filed return or assessment in \(String(store.year)) yet.", systemImage: "doc.badge.plus").foregroundStyle(.orange)
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        GridRow { Text("Line").bold(); Text("").bold(); Text("As filed").bold(); Text("Draft").bold(); Text("Change").bold() }
                        ForEach(lines) { l in
                            let a = filed[l.id], b = totals[l.id]
                            GridRow {
                                Text(l.code).font(.system(size: 11, design: .monospaced))
                                Text(l.title)
                                Text(a.map { Amounts.format($0, info.country) } ?? "—").monospacedDigit()
                                Text(b.map { Amounts.format($0, info.country) } ?? "—").monospacedDigit()
                                if let a, let b, a != b {
                                    Text(Amounts.format(b - a, info.country)).monospacedDigit().foregroundStyle(b > a ? .orange : .green)
                                } else { Text("") }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: { Text("Refiling").font(.headline) }
    }
}

// MARK: Forms & engines

struct EnginesView: View {
    @Environment(TaxStore.self) private var store
    @State private var status = ""
    @State private var working = false
    @State private var log = ""
    @State private var setup = CanadaEngine.findTools()

    var body: some View {
        let info = store.info
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if info.country == .canada { canada(info) } else { us(info) }
            }
            .padding(20)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Canada

    @ViewBuilder private func canada(_ info: TaxYearInfo) -> some View {
        let forms = CanadaEngine.localForms(province: info.province, year: store.year)
        let supported = CanadaEngine.t1Package[info.province] != nil
        let out = CanadaEngine.folder(province: info.province, year: store.year)
        Text("Fill the CRA's own forms").font(.title2.weight(.bold))
        Text("Uses **canadian-income-tax** (open source, GPL-3.0), which completes the CRA's fillable T1, the provincial 428 and 479, and the federal schedules from your amounts and T4 slips. The result is a set of official forms your preparer can check, sign and file.")
            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Link("github.com/blamario/canadian-income-tax", destination: URL(string: "https://github.com/blamario/canadian-income-tax")!).font(.caption)

        if !supported {
            Label("The engine completes the provincial forms for ON, BC, AB and MB. For \(info.province), use the Draft Return and Preparer Package.", systemImage: "info.circle").foregroundStyle(.orange)
        }

        step(1, "Get the blank \(String(store.year)) forms", done: forms != nil) {
            Text("Downloads the fillable T1, \(info.province)428\(CanadaEngine.with479.contains(info.province) ? ", \(info.province)479" : "") and T4 from canada.ca.").font(.caption).foregroundStyle(.secondary)
            Button(forms == nil ? "Download from canada.ca" : "Downloaded ✓") {
                working = true; status = "Downloading…"
                Task {
                    do { _ = try await CanadaEngine.download(province: info.province, year: store.year); status = "Forms downloaded." }
                    catch { status = error.localizedDescription }
                    working = false
                }
            }
            .disabled(!supported || working || forms != nil)
        }

        step(2, "Fill them with your slips", done: FileManager.default.fileExists(atPath: out.appendingPathComponent("Inputs/T1 inputs.pdf").path)) {
            Text("Writes each T4 onto a T4 form and every other amount of the draft onto the T1. Check your T4 slips are marked as checked first.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Fill Forms") {
                    guard let forms else { return }
                    do {
                        let r = try CanadaEngine.prepare(store: store, forms: forms, into: out.appendingPathComponent("Inputs"))
                        status = "Filled the T1 and \(r.t4s.count) T4 form\(r.t4s.count == 1 ? "" : "s")."
                    } catch { status = error.localizedDescription }
                }
                .disabled(forms == nil)
                Button("Show in Finder") { NSWorkspace.shared.open(out) }
            }
        }

        step(3, "Complete them with the engine", done: FileManager.default.fileExists(atPath: out.appendingPathComponent("Completed").path)) {
            if setup.ready {
                Label("Found \(setup.engine!.path) and pdftk", systemImage: "checkmark.seal.fill").font(.caption).foregroundStyle(.green)
                Button(working ? "Working…" : "Run canadian-income-tax") {
                    guard let forms else { return }
                    working = true; status = "Completing the forms…"
                    let inputs = out.appendingPathComponent("Inputs")
                    Task {
                        do {
                            let r = try CanadaEngine.prepare(store: store, forms: forms, into: inputs)
                            let done = out.appendingPathComponent("Completed")
                            try? FileManager.default.removeItem(at: done)
                            TaxPaths.make(done)
                            log = try await CanadaEngine.run(setup: setup, province: info.province, t1: r.t1, t4s: r.t4s, p428: forms.p428, p479: forms.p479, out: done)
                            status = "Done: the completed forms are in the Completed folder, and go into the preparer package."
                            NSWorkspace.shared.open(done)
                        } catch { status = error.localizedDescription }
                        working = false
                    }
                }
                .disabled(forms == nil || working)
            } else {
                Text("The engine isn't installed. It's a free command-line program; install it once with these commands in Terminal (it takes a while to build):")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ForEach(CanadaEngine.installCommands, id: \.self) { c in
                    HStack {
                        Text(c).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                            .padding(6).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                        Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(c, forType: .string) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain)
                    }
                }
                Button("Check Again") { setup = CanadaEngine.findTools() }
                Text("Without it, the filled T1 and T4 forms from step 2 still go to your preparer; the calculated lines are then left for them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }

        if !status.isEmpty { Label(status, systemImage: "info.circle").fixedSize(horizontal: false, vertical: true) }
        if !log.isEmpty {
            DisclosureGroup("Engine output") { Text(log).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
        }
    }

    // MARK: US

    @ViewBuilder private func us(_ info: TaxYearInfo) -> some View {
        Text("Open your draft in UsTaxes").font(.title2.weight(.bold))
        Text("**UsTaxes** (open source, AGPL-3.0) prepares Form 1040, its schedules and several state returns, and runs entirely in your browser; your data stays on this Mac. Save the file below, open UsTaxes, and use Load on its first page.")
            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        HStack {
            Button("Save File for UsTaxes…") {
                guard let data = UsTaxesExport.json(store: store) else { return }
                let p = NSSavePanel()
                p.nameFieldStringValue = "ustaxes-\(store.year).json"
                p.allowedContentTypes = [.json]
                if p.runModal() == .OK, let u = p.url { try? data.write(to: u); status = "Saved. In UsTaxes choose Load and pick this file." }
            }
            .buttonStyle(.borderedProminent).tint(TX.accent)
            Link("Open UsTaxes ↗", destination: URL(string: "https://ustaxes.org")!)
        }
        let notCarried = store.documents.filter { UsTaxesExport.notCarried[$0.specID] != nil }
        if !notCarried.isEmpty {
            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(notCarried) { d in Text("• \(d.spec.code) from \(d.payer.isEmpty ? d.fileName : d.payer) → \(UsTaxesExport.notCarried[d.specID]!)") }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: { Text("Enter these in UsTaxes by hand").font(.headline) }
        }
        Text("Prefer a desktop program? **OpenTaxSolver** (GPL) covers Form 1040 and many states: copy the draft's lines below and type them into its form.")
            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        HStack {
            Button("Copy Draft Lines") {
                let text = store.draft().map { "\($0.line.code)\t\($0.line.title)\t\(Amounts.plain($0.total))" }.joined(separator: "\n")
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                status = "Copied \(store.draft().count) lines."
            }
            Link("OpenTaxSolver ↗", destination: URL(string: "https://opentaxsolver.sourceforge.net")!)
        }
        if !status.isEmpty { Label(status, systemImage: "info.circle") }
    }

    private func step<C: View>(_ n: Int, _ title: String, done: Bool, @ViewBuilder _ content: () -> C) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : TX.accent).frame(width: 26, height: 26)
                if done { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white) }
                else { Text("\(n)").font(.system(size: 13, weight: .bold)).foregroundStyle(.white) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                content()
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: Preparer package

struct PacketView: View {
    @Environment(TaxStore.self) private var store
    @State private var options = PacketBuilder.Options()
    @State private var status = ""

    var body: some View {
        let docs = store.documents
        let unchecked = docs.filter { $0.status != .reviewed }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Package for your tax preparer").font(.title2.weight(.bold))
                Text("One PDF with a cover page, the draft's lines and where every amount came from, a list of your documents, your questions\(store.info.amending ? ", what changes from the return as filed" : ""), then the filled forms and every original document. Bring it to your preparer to check, complete and file.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !unchecked.isEmpty {
                    Label("\(unchecked.count) document\(unchecked.count == 1 ? " hasn't" : "s haven't") been checked yet; they're marked “not checked” in the package.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                Toggle("Include the original documents", isOn: $options.includeOriginals)
                if store.info.country == .canada { Toggle("Include the completed CRA forms (Forms & Engines)", isOn: $options.includeForms) }
                HStack {
                    Button("Create Package…") {
                        let p = NSSavePanel()
                        p.nameFieldStringValue = "Tax draft \(store.year).pdf"
                        p.allowedContentTypes = [.pdf]
                        guard p.runModal() == .OK, let u = p.url else { return }
                        do {
                            let n = try PacketBuilder.build(store: store, options: options, to: u)
                            status = "Created a \(n)-page package."
                            NSWorkspace.shared.open(u)
                        } catch { status = "Couldn't create it: \(error.localizedDescription)" }
                    }
                    .buttonStyle(.borderedProminent).tint(TX.accent).controlSize(.large).disabled(docs.isEmpty)
                    Button("Export Values as CSV…") { exportCSV() }.disabled(docs.isEmpty)
                }
                if !status.isEmpty { Label(status, systemImage: "checkmark.circle") }
                Divider()
                Text("Everything stays on this Mac. Imported documents are copied into ~/Library/Application Support/TaxDesk, which only your user account can open, and the app asks for Touch ID or your password to show them.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Ask for Touch ID or password when opening", isOn: Binding(get: { store.library.requireUnlock }, set: { store.library.requireUnlock = $0; store.save() }))
                    .font(.caption)
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func exportCSV() {
        var rows = [["Document", "Issued by", "Box", "Label", "Value", "Line", "Checked"]]
        for d in store.documents {
            for f in d.spec.fields {
                guard let v = d.fields[f.key] else { continue }
                rows.append([d.spec.code, d.payer, f.key, f.label, v.value, f.lines.joined(separator: " "), d.status == .reviewed ? "yes" : "no"])
            }
        }
        let csv = rows.map { $0.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",") }.joined(separator: "\n")
        let p = NSSavePanel()
        p.nameFieldStringValue = "Tax values \(store.year).csv"
        p.allowedContentTypes = [.commaSeparatedText]
        if p.runModal() == .OK, let u = p.url { try? csv.write(to: u, atomically: true, encoding: .utf8); status = "Saved the values." }
    }
}

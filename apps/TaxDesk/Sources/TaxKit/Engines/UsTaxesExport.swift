import Foundation

/// Writes a file for UsTaxes (ustaxes.org, AGPL-3.0), an open-source US federal and state return
/// app that runs in the browser without sending your data anywhere. Its "Load" button reads this
/// file; UsTaxes then fills Form 1040 and its schedules and can save them as PDFs.
///
/// The layout follows UsTaxes' saved-state format: one `Information` per tax year ("Y2025"),
/// plus `assets` and `activeYear`. Only what the slips hold is written; names, SSNs, filing
/// status and anything else are entered in UsTaxes.
enum UsTaxesExport {
    @MainActor
    static func json(store: TaxStore) -> Data? {
        let docs = store.documents.filter { $0.spec.country == .us }
        func m(_ d: TaxDocument, _ k: String) -> Double { d.fields[k]?.amount ?? 0 }
        func payer(_ d: TaxDocument) -> String { d.payer.isEmpty ? d.fileName : d.payer }
        let state = store.info.usState.isEmpty ? nil : store.info.usState.uppercased()

        var w2s: [[String: Any]] = []
        var f1099s: [[String: Any]] = []
        var f1098es: [[String: Any]] = []
        for d in docs {
            switch d.specID {
            case "US.W2":
                var w: [String: Any] = [
                    "occupation": "", "income": m(d, "1"), "fedWithholding": m(d, "2"), "ssWages": m(d, "3"), "ssWithholding": m(d, "4"),
                    "medicareIncome": m(d, "5"), "medicareWithholding": m(d, "6"), "personRole": "PRIMARY",
                    "employer": ["employerName": payer(d), "EIN": (d.fields["ein"]?.value ?? "").filter(\.isNumber)],
                ]
                if let state { w["state"] = state; w["stateWages"] = m(d, "16"); w["stateWithholding"] = m(d, "17") }
                w2s.append(w)
            case "US.1099INT":
                f1099s.append(["payer": payer(d), "type": "INT", "personRole": "PRIMARY", "form": ["income": m(d, "1")]])
            case "US.1099DIV":
                f1099s.append(["payer": payer(d), "type": "DIV", "personRole": "PRIMARY",
                               "form": ["dividends": m(d, "1a"), "qualifiedDividends": m(d, "1b"), "totalCapitalGainsDistributions": m(d, "2a")]])
            case "US.1099R":
                f1099s.append(["payer": payer(d), "type": "R", "personRole": "PRIMARY",
                               "form": ["grossDistribution": m(d, "1"), "taxableAmount": m(d, "2a"), "federalIncomeTaxWithheld": m(d, "4"), "planType": "Pension"]])
            case "US.SSA1099":
                f1099s.append(["payer": "Social Security Administration", "type": "SSA", "personRole": "PRIMARY",
                               "form": ["netBenefits": m(d, "5"), "federalIncomeTaxWithheld": m(d, "6")]])
            case "US.1098E":
                f1098es.append(["lender": payer(d), "interest": m(d, "1")])
            default: break
            }
        }
        let information: [String: Any] = [
            "f1099s": f1099s, "w2s": w2s, "estimatedTaxes": [], "realEstate": [], "taxPayer": ["dependents": []], "questions": [:],
            "f1098es": f1098es, "f3921s": [], "scheduleK1Form1065s": [], "stateResidencies": state.map { [["state": $0]] } ?? [],
            "healthSavingsAccounts": [], "credits": [], "individualRetirementArrangements": [],
        ]
        let key = "Y\(store.year)"
        let state_: [String: Any] = [key: information, "assets": [], "activeYear": key]
        return try? JSONSerialization.data(withJSONObject: state_, options: [.prettyPrinted, .sortedKeys])
    }

    /// Slips UsTaxes has no import for; they're listed for the preparer instead.
    static let notCarried = ["US.1099NEC": "Schedule C", "US.1099MISC": "Schedule 1 / E", "US.1099G": "Schedule 1", "US.1098": "Schedule A", "US.1098T": "Form 8863"]
}

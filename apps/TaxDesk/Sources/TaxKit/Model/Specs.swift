import Foundation

/// Which tax system a slip or line belongs to.
enum Country: String, Codable, CaseIterable, Identifiable {
    case canada = "CA", us = "US"
    var id: String { rawValue }
    var name: String { self == .canada ? "Canada" : "United States" }
    var flag: String { self == .canada ? "🇨🇦" : "🇺🇸" }
}

/// One box of a slip: where it sits, what it's called, and which line of the return it feeds.
struct FieldSpec: Hashable {
    enum Kind: String, Codable { case money, text, year, province }
    /// Box number as printed ("14", "016", "1a"), or a name for unnumbered fields ("payer").
    let key: String
    let label: String
    /// Other wordings of the label to look for, including French on Canadian slips.
    var aliases: [String] = []
    var kind: Kind = .money
    /// Return lines the amount goes to ("10100"; "1a" on the 1040).
    var lines: [String] = []
    /// The field's name in the government's fillable PDF of this slip, when there is one.
    var formField: String? = nil
}

/// A kind of tax document and how to recognise and read it.
struct SlipSpec: Identifiable, Hashable {
    let id: String
    let country: Country
    let code: String
    let title: String
    /// Phrases printed on the document; the one with the most matches wins.
    let keywords: [String]
    let fields: [FieldSpec]
    /// A past return or assessment, compared against the draft when refiling.
    var isReturn = false

    static func == (a: SlipSpec, b: SlipSpec) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    func field(_ key: String) -> FieldSpec? { fields.first { $0.key == key } }
}

private func money(_ key: String, _ label: String, _ aliases: [String] = [], _ lines: [String] = [], form: String? = nil) -> FieldSpec {
    FieldSpec(key: key, label: label, aliases: aliases, kind: .money, lines: lines, formField: form)
}
private func text(_ key: String, _ label: String, _ aliases: [String] = [], form: String? = nil) -> FieldSpec {
    FieldSpec(key: key, label: label, aliases: aliases, kind: .text, formField: form)
}
private let yearField = FieldSpec(key: "year", label: "Tax year", aliases: ["Year", "Année", "Tax year", "Calendar year", "For calendar year"], kind: .year, formField: "Year")

enum Specs {
    static let other = SlipSpec(id: "other", country: .canada, code: "Other", title: "Other document", keywords: [], fields: [yearField, text("payer", "Issued by")])

    // MARK: Canada

    static let canada: [SlipSpec] = [
        SlipSpec(id: "CA.T4", country: .canada, code: "T4", title: "T4 – Statement of Remuneration Paid",
                 keywords: ["Statement of Remuneration Paid", "État de la rémunération payée", "T4"],
                 fields: [
                    yearField,
                    text("payer", "Employer's name", ["Employer's name", "Nom de l'employeur"], form: "EmployersName"),
                    FieldSpec(key: "10", label: "Province of employment", aliases: ["Province of employment", "Province d'emploi"], kind: .province, formField: "Box10"),
                    money("14", "Employment income", ["Employment income", "Revenus d'emploi"], ["10100"], form: "Box14"),
                    money("16", "Employee's CPP contributions", ["Employee's CPP contributions", "Cotisations de l'employé au RPC"], ["30800"], form: "Box16"),
                    money("16A", "Employee's second CPP contributions", ["second CPP contributions", "Deuxièmes cotisations de l'employé au RPC"], ["22215"], form: "Box16A"),
                    money("17", "Employee's QPP contributions", ["QPP contributions", "cotisations au RRQ"], ["30800"], form: "Box17"),
                    money("18", "Employee's EI premiums", ["EI premiums", "El premiums", "Cotisations de l'employé à l'AE"], ["31200"], form: "Box18"),
                    money("20", "RPP contributions", ["RPP contributions", "Cotisations à un RPA"], ["20700"], form: "Box20"),
                    money("22", "Income tax deducted", ["Income tax deducted", "Impôt sur le revenu retenu"], ["43700"], form: "Box22"),
                    money("24", "EI insurable earnings", ["EI insurable earnings", "insurable earnings", "Gains assurables d'AE"], form: "Box24"),
                    money("26", "CPP/QPP pensionable earnings", ["pensionable earnings", "Gains ouvrant droit à pension"], form: "Box26"),
                    money("44", "Union dues", ["Union dues", "Cotisations syndicales"], ["21200"], form: "Box44"),
                    money("46", "Charitable donations", ["Charitable donations", "Dons de bienfaisance"], ["34900"], form: "Box46"),
                    money("52", "Pension adjustment", ["Pension adjustment", "Facteur d'équivalence"], ["20600"], form: "Box52"),
                    money("55", "Employee's PPIP premiums", ["PPIP premiums", "Cotisations de l'employé au RPAP"], form: "Box55"),
                 ]),
        SlipSpec(id: "CA.T4A", country: .canada, code: "T4A", title: "T4A – Pension, Retirement, Annuity and Other Income",
                 keywords: ["Statement of Pension, Retirement, Annuity", "État du revenu de pension", "T4A"],
                 fields: [
                    yearField, text("payer", "Payer's name", ["Payer's name", "Nom du payeur"]),
                    money("016", "Pension or superannuation", ["Pension or superannuation", "Prestations de retraite"], ["11500"]),
                    money("018", "Lump-sum payments", ["Lump-sum payments", "Paiements forfaitaires"], ["13000"]),
                    money("020", "Self-employed commissions", ["Self-employed commissions", "Commissions d'un travail indépendant"], ["13900"]),
                    money("022", "Income tax deducted", ["Income tax deducted", "Impôt sur le revenu retenu"], ["43700"]),
                    money("024", "Annuities", ["Annuities", "Rentes"], ["11500"]),
                    money("028", "Other income", ["Other income", "Autres revenus"], ["13000"]),
                    money("048", "Fees for services", ["Fees for services", "Honoraires ou autres sommes"], ["13500"]),
                    money("105", "Scholarships, bursaries, fellowships", ["Scholarships", "Bourses d'études"], ["13010"]),
                    money("107", "Wage loss replacement plan", ["Wage loss replacement", "Régime d'assurance-salaire"], ["10400"]),
                 ]),
        SlipSpec(id: "CA.T4E", country: .canada, code: "T4E", title: "T4E – Employment Insurance and Other Benefits",
                 keywords: ["Statement of Employment Insurance", "État des prestations d'assurance-emploi", "T4E"],
                 fields: [yearField, text("payer", "Issued by"),
                          money("14", "Total benefits paid", ["Total benefits paid", "Total des prestations versées"], ["11900"]),
                          money("22", "Income tax deducted", ["Income tax deducted", "Impôt sur le revenu retenu"], ["43700"])]),
        SlipSpec(id: "CA.T4AP", country: .canada, code: "T4A(P)", title: "T4A(P) – Canada Pension Plan Benefits",
                 keywords: ["Statement of Canada Pension Plan Benefits", "Prestations du Régime de pensions du Canada", "T4A(P)"],
                 fields: [yearField, text("payer", "Issued by"),
                          money("20", "Taxable CPP benefits", ["Taxable CPP benefits", "Prestations imposables du RPC"], ["11400"]),
                          money("22", "Income tax deducted", ["Income tax deducted", "Impôt sur le revenu retenu"], ["43700"])]),
        SlipSpec(id: "CA.T4AOAS", country: .canada, code: "T4A(OAS)", title: "T4A(OAS) – Old Age Security",
                 keywords: ["Statement of Old Age Security", "Relevé de la sécurité de la vieillesse", "T4A(OAS)"],
                 fields: [yearField, text("payer", "Issued by"),
                          money("18", "Taxable pension paid", ["Taxable pension paid", "Pension imposable payée"], ["11300"]),
                          money("22", "Income tax deducted", ["Income tax deducted", "Impôt sur le revenu retenu"], ["43700"])]),
        SlipSpec(id: "CA.T5", country: .canada, code: "T5", title: "T5 – Statement of Investment Income",
                 keywords: ["Statement of Investment Income", "État des revenus de placement", "T5"],
                 fields: [yearField, text("payer", "Payer's name", ["Payer's name", "Nom du payeur"]),
                          money("13", "Interest from Canadian sources", ["Interest from Canadian sources", "Intérêts de source canadienne"], ["12100"]),
                          money("24", "Actual amount of eligible dividends", ["Actual amount of eligible dividends", "Montant réel des dividendes déterminés"]),
                          money("25", "Taxable amount of eligible dividends", ["Taxable amount of eligible dividends", "Montant imposable des dividendes déterminés"], ["12000"]),
                          money("10", "Actual amount of other dividends", ["Actual amount of dividends other than eligible", "dividendes autres que"]),
                          money("11", "Taxable amount of other dividends", ["Taxable amount of dividends other than eligible", "Montant imposable des dividendes autres"], ["12000", "12010"]),
                          money("18", "Capital gains dividends", ["Capital gains dividends", "Dividendes sur gains en capital"], ["12700"]),
                          money("15", "Foreign income", ["Foreign income", "Revenus étrangers"], ["12100"]),
                          money("16", "Foreign tax paid", ["Foreign tax paid", "Impôt étranger payé"])]),
        SlipSpec(id: "CA.T3", country: .canada, code: "T3", title: "T3 – Trust Income Allocations",
                 keywords: ["Statement of Trust Income Allocations", "État des revenus de fiducie", "T3"],
                 fields: [yearField, text("payer", "Trust's name", ["Trust's name", "Nom de la fiducie"]),
                          money("21", "Capital gains", ["Capital gains", "Gains en capital"], ["12700"]),
                          money("26", "Other income", ["Other income", "Autres revenus"], ["13000"]),
                          money("50", "Taxable amount of eligible dividends", ["Taxable amount of eligible dividends"], ["12000"]),
                          money("32", "Taxable amount of other dividends", ["Taxable amount of dividends other than eligible"], ["12000", "12010"]),
                          money("25", "Foreign non-business income", ["Foreign non-business income", "Revenu étranger non tiré"], ["12100"])]),
        SlipSpec(id: "CA.T5008", country: .canada, code: "T5008", title: "T5008 – Securities Transactions",
                 keywords: ["Statement of Securities Transactions", "État des opérations sur titres", "T5008"],
                 fields: [yearField, text("payer", "Issued by"),
                          money("20", "Cost or book value", ["Cost or book value", "Coût ou valeur comptable"]),
                          money("21", "Proceeds of disposition", ["Proceeds of disposition", "Produit de disposition"])]),
        SlipSpec(id: "CA.RRSP", country: .canada, code: "RRSP", title: "RRSP contribution receipt",
                 keywords: ["RRSP", "Retirement Savings Plan", "Contribution receipt", "REER"],
                 fields: [yearField, text("payer", "Issued by"),
                          money("amount", "Contribution amount", ["Contribution amount", "Amount of contribution", "Montant de la cotisation", "Total"], ["20800"])]),
        SlipSpec(id: "CA.T2202", country: .canada, code: "T2202", title: "T2202 – Tuition and Enrolment Certificate",
                 keywords: ["Tuition and Enrolment Certificate", "Certificat pour frais de scolarité", "T2202"],
                 fields: [yearField, text("payer", "School", ["Name and address of designated", "Educational institution"]),
                          money("23", "Eligible tuition fees", ["Eligible tuition fees", "Frais de scolarité admissibles", "Total eligible tuition fees"], ["32300"])]),
        SlipSpec(id: "CA.Donation", country: .canada, code: "Donation", title: "Donation receipt",
                 keywords: ["Official receipt for income tax purposes", "Official donation receipt", "Reçu officiel aux fins de l'impôt", "Charitable registration"],
                 fields: [yearField, text("payer", "Charity"),
                          money("amount", "Eligible amount of gift", ["Eligible amount", "Amount of gift", "Montant admissible", "Total"], ["34900"])]),
        SlipSpec(id: "CA.Medical", country: .canada, code: "Medical", title: "Medical expense receipt",
                 keywords: ["Pharmacy", "Prescription", "Dental", "Optometr", "Physiotherap", "Medical", "Paramedical"],
                 fields: [yearField, text("payer", "Provider"), money("amount", "Amount paid", ["Amount paid", "Total", "Paid", "Patient pays"], ["33099"])]),
        SlipSpec(id: "CA.Rent", country: .canada, code: "Rent", title: "Rent or property tax receipt",
                 keywords: ["Rent receipt", "Rent paid", "Property tax", "Loyer", "Impôt foncier"],
                 fields: [yearField, text("payer", "Landlord or municipality"), money("amount", "Amount paid", ["Total rent", "Rent paid", "Total", "Amount"], ["ON479"])]),
        SlipSpec(id: "CA.NOA", country: .canada, code: "NOA", title: "Notice of Assessment", keywords: ["Notice of Assessment", "Avis de cotisation", "Notice of Reassessment"],
                 fields: [yearField,
                          money("15000", "Total income", ["Total income", "Revenu total"], ["15000"]),
                          money("23600", "Net income", ["Net income", "Revenu net"], ["23600"]),
                          money("26000", "Taxable income", ["Taxable income", "Revenu imposable"], ["26000"]),
                          money("43700", "Total income tax deducted", ["Total income tax deducted"], ["43700"]),
                          money("48400", "Refund", ["Refund", "Remboursement"], ["48400"]),
                          money("48500", "Balance owing", ["Balance owing", "Solde dû"], ["48500"]),
                          money("rrsp", "RRSP deduction limit", ["RRSP deduction limit", "Maximum déductible au titre des REER"])],
                 isReturn: true),
        SlipSpec(id: "CA.T1", country: .canada, code: "T1", title: "T1 Income Tax and Benefit Return (as filed)",
                 keywords: ["Income Tax and Benefit Return", "Déclaration de revenus et de prestations", "T1 General"],
                 fields: [yearField,
                          money("10100", "Employment income", ["10100"], ["10100"]),
                          money("12100", "Interest and other investment income", ["12100"], ["12100"]),
                          money("15000", "Total income", ["15000"], ["15000"]),
                          money("20800", "RRSP deduction", ["20800"], ["20800"]),
                          money("23600", "Net income", ["23600"], ["23600"]),
                          money("26000", "Taxable income", ["26000"], ["26000"]),
                          money("43500", "Total payable", ["43500"], ["43500"]),
                          money("43700", "Total income tax deducted", ["43700"], ["43700"]),
                          money("48400", "Refund", ["48400"], ["48400"]),
                          money("48500", "Balance owing", ["48500"], ["48500"])],
                 isReturn: true),
    ]

    // MARK: United States

    static let us: [SlipSpec] = [
        SlipSpec(id: "US.W2", country: .us, code: "W-2", title: "W-2 – Wage and Tax Statement",
                 keywords: ["Wage and Tax Statement", "W-2"],
                 fields: [yearField, text("payer", "Employer's name", ["Employer's name, address", "Employer’s name"]),
                          text("ein", "Employer identification number", ["Employer identification number", "EIN"]),
                          money("1", "Wages, tips, other compensation", ["Wages, tips, other compensation"], ["1a"]),
                          money("2", "Federal income tax withheld", ["Federal income tax withheld"], ["25a"]),
                          money("3", "Social security wages", ["Social security wages"]),
                          money("4", "Social security tax withheld", ["Social security tax withheld"]),
                          money("5", "Medicare wages and tips", ["Medicare wages and tips"]),
                          money("6", "Medicare tax withheld", ["Medicare tax withheld"]),
                          money("16", "State wages", ["State wages, tips"]),
                          money("17", "State income tax", ["State income tax"])]),
        SlipSpec(id: "US.1099INT", country: .us, code: "1099-INT", title: "1099-INT – Interest Income",
                 keywords: ["1099-INT", "Interest Income"],
                 fields: [yearField, text("payer", "Payer's name", ["PAYER'S name", "Payer’s name"]),
                          money("1", "Interest income", ["Interest income"], ["2b"]),
                          money("3", "Interest on U.S. Savings Bonds", ["Interest on U.S. Savings Bonds"]),
                          money("4", "Federal income tax withheld", ["Federal income tax withheld"], ["25b"]),
                          money("8", "Tax-exempt interest", ["Tax-exempt interest"], ["2a"])]),
        SlipSpec(id: "US.1099DIV", country: .us, code: "1099-DIV", title: "1099-DIV – Dividends and Distributions",
                 keywords: ["1099-DIV", "Dividends and Distributions"],
                 fields: [yearField, text("payer", "Payer's name", ["PAYER'S name", "Payer’s name"]),
                          money("1a", "Total ordinary dividends", ["Total ordinary dividends"], ["3b"]),
                          money("1b", "Qualified dividends", ["Qualified dividends"], ["3a"]),
                          money("2a", "Total capital gain distributions", ["Total capital gain distr"], ["7"]),
                          money("4", "Federal income tax withheld", ["Federal income tax withheld"], ["25b"])]),
        SlipSpec(id: "US.1099NEC", country: .us, code: "1099-NEC", title: "1099-NEC – Nonemployee Compensation",
                 keywords: ["1099-NEC", "Nonemployee Compensation"],
                 fields: [yearField, text("payer", "Payer's name", ["PAYER'S name", "Payer’s name"]),
                          money("1", "Nonemployee compensation", ["Nonemployee compensation"], ["S1-3"]),
                          money("4", "Federal income tax withheld", ["Federal income tax withheld"], ["25b"])]),
        SlipSpec(id: "US.1099MISC", country: .us, code: "1099-MISC", title: "1099-MISC – Miscellaneous Information",
                 keywords: ["1099-MISC", "Miscellaneous Information", "Miscellaneous Income"],
                 fields: [yearField, text("payer", "Payer's name", ["PAYER'S name", "Payer’s name"]),
                          money("1", "Rents", ["Rents"], ["S1-5"]),
                          money("3", "Other income", ["Other income"], ["S1-8z"]),
                          money("4", "Federal income tax withheld", ["Federal income tax withheld"], ["25b"])]),
        SlipSpec(id: "US.1099R", country: .us, code: "1099-R", title: "1099-R – Distributions From Pensions, IRAs",
                 keywords: ["1099-R", "Distributions From Pensions"],
                 fields: [yearField, text("payer", "Payer's name", ["PAYER'S name", "Payer’s name"]),
                          money("1", "Gross distribution", ["Gross distribution"]),
                          money("2a", "Taxable amount", ["Taxable amount"], ["5b"]),
                          money("4", "Federal income tax withheld", ["Federal income tax withheld"], ["25b"])]),
        SlipSpec(id: "US.1099G", country: .us, code: "1099-G", title: "1099-G – Certain Government Payments",
                 keywords: ["1099-G", "Certain Government Payments"],
                 fields: [yearField, text("payer", "Payer's name", ["PAYER'S name"]),
                          money("1", "Unemployment compensation", ["Unemployment compensation"], ["S1-7"]),
                          money("2", "State or local income tax refunds", ["State or local income tax refunds"], ["S1-1"]),
                          money("4", "Federal income tax withheld", ["Federal income tax withheld"], ["25b"])]),
        SlipSpec(id: "US.SSA1099", country: .us, code: "SSA-1099", title: "SSA-1099 – Social Security Benefit Statement",
                 keywords: ["SSA-1099", "Social Security Benefit Statement"],
                 fields: [yearField, money("5", "Net benefits", ["Net Benefits"], ["6a"]),
                          money("6", "Voluntary federal income tax withheld", ["Voluntary Federal Income Tax Withheld"], ["25b"])]),
        SlipSpec(id: "US.1098", country: .us, code: "1098", title: "1098 – Mortgage Interest Statement",
                 keywords: ["Mortgage Interest Statement", "1098"],
                 fields: [yearField, text("payer", "Lender", ["RECIPIENT'S/LENDER'S name"]),
                          money("1", "Mortgage interest received", ["Mortgage interest received"], ["A-8a"])]),
        SlipSpec(id: "US.1098E", country: .us, code: "1098-E", title: "1098-E – Student Loan Interest Statement",
                 keywords: ["Student Loan Interest Statement", "1098-E"],
                 fields: [yearField, text("payer", "Lender", ["RECIPIENT'S/LENDER'S name"]),
                          money("1", "Student loan interest received", ["Student loan interest received"], ["S1-21"])]),
        SlipSpec(id: "US.1098T", country: .us, code: "1098-T", title: "1098-T – Tuition Statement",
                 keywords: ["Tuition Statement", "1098-T"],
                 fields: [yearField, text("payer", "School", ["FILER'S name"]),
                          money("1", "Payments received for qualified tuition", ["Payments received for qualified tuition"], ["8863"]),
                          money("5", "Scholarships or grants", ["Scholarships or grants"])]),
        SlipSpec(id: "US.1040", country: .us, code: "1040", title: "Form 1040 (as filed)",
                 keywords: ["U.S. Individual Income Tax Return", "Form 1040"],
                 fields: [yearField,
                          money("1a", "Wages", ["Total amount from Form(s) W-2"], ["1a"]),
                          money("9", "Total income", ["This is your total income"], ["9"]),
                          money("11", "Adjusted gross income", ["adjusted gross income"], ["11"]),
                          money("15", "Taxable income", ["This is your taxable income"], ["15"]),
                          money("24", "Total tax", ["This is your total tax"], ["24"]),
                          money("33", "Total payments", ["These are your total payments"], ["33"]),
                          money("34", "Overpaid", ["amount you overpaid"], ["34"]),
                          money("37", "Amount you owe", ["Amount you owe"], ["37"])],
                 isReturn: true),
    ]

    static let all: [SlipSpec] = canada + us + [other]

    static func spec(_ id: String) -> SlipSpec { all.first { $0.id == id } ?? other }
}

/// A line of the return that slips add up to.
struct ReturnLine: Identifiable, Hashable {
    enum Section: String, CaseIterable { case income = "Income", deductions = "Deductions", credits = "Credits", payments = "Tax paid", totals = "Totals from the return" }
    let id: String
    let country: Country
    let title: String
    let section: Section
    /// Explains what happens next, where a line needs a schedule or a limit applied.
    var note: String? = nil
    /// The T1 field (Ontario form) the engine reads this line from.
    var t1Field: String? = nil

    var code: String { id.hasPrefix("S1-") ? "Sch. 1 line \(id.dropFirst(3))" : id.hasPrefix("A-") ? "Sch. A line \(id.dropFirst(2))" : country == .canada && id.allSatisfy(\.isNumber) ? "Line \(id)" : country == .us ? "Line \(id)" : id }

    static let canada: [ReturnLine] = [
        .init(id: "10100", country: .canada, title: "Employment income", section: .income, t1Field: "Page3.Line1.Line_10100_Amount"),
        .init(id: "10400", country: .canada, title: "Other employment income", section: .income, t1Field: "Page3.Line10400.Line_10400_Amount"),
        .init(id: "11300", country: .canada, title: "Old Age Security pension", section: .income, t1Field: "Page3.Line11300.Line_11300_Amount"),
        .init(id: "11400", country: .canada, title: "CPP or QPP benefits", section: .income, t1Field: "Page3.Line11400.Line_11400_Amount"),
        .init(id: "11500", country: .canada, title: "Other pensions and superannuation", section: .income, t1Field: "Page3.Line11500.Line_11500_Amount"),
        .init(id: "11900", country: .canada, title: "Employment Insurance benefits", section: .income, t1Field: "Page3.Line11900.Line_11900_Amount"),
        .init(id: "12000", country: .canada, title: "Taxable dividends (eligible and other)", section: .income, t1Field: "Page3.Line12000.Line_12000_Amount"),
        .init(id: "12010", country: .canada, title: "Taxable dividends other than eligible", section: .income, t1Field: "Page3.Line12010.Line_12010_Amount"),
        .init(id: "12100", country: .canada, title: "Interest and other investment income", section: .income, t1Field: "Page3.Line12100.Line_12100_Amount"),
        .init(id: "12700", country: .canada, title: "Capital gains", section: .income, note: "Goes through Schedule 3; only the taxable part is on line 12700."),
        .init(id: "13000", country: .canada, title: "Other income", section: .income, t1Field: "Page3.Line13000.Line_13000_Amount"),
        .init(id: "13010", country: .canada, title: "Taxable scholarships and bursaries", section: .income, note: "Often fully exempt for full-time students.", t1Field: "Page3.Line13010.Line_13010_Amount"),
        .init(id: "13500", country: .canada, title: "Business income (fees for services)", section: .income, note: "Needs form T2125 with your expenses."),
        .init(id: "13900", country: .canada, title: "Commission income (self-employed)", section: .income, note: "Needs form T2125."),
        .init(id: "20600", country: .canada, title: "Pension adjustment", section: .deductions, note: "Reduces next year's RRSP room.", t1Field: "Page4.Line20600.Line_20600_Amount"),
        .init(id: "20700", country: .canada, title: "RPP deduction", section: .deductions, t1Field: "Page4.Line20700.Line_20700_Amount"),
        .init(id: "20800", country: .canada, title: "RRSP deduction", section: .deductions, note: "Limited by your RRSP deduction limit (on last year's Notice of Assessment); needs Schedule 7.", t1Field: "Page4.Line20800.Line_20800_Amount"),
        .init(id: "21200", country: .canada, title: "Union and professional dues", section: .deductions, t1Field: "Page4.Line21200.Line_21200_Amount"),
        .init(id: "22215", country: .canada, title: "Enhanced CPP contributions", section: .deductions, note: "Worked out on Schedule 8."),
        .init(id: "30800", country: .canada, title: "CPP or QPP contributions", section: .credits, note: "Worked out on Schedule 8."),
        .init(id: "31200", country: .canada, title: "Employment Insurance premiums", section: .credits, t1Field: "Page6.PartB.Line31200.Line_31200_Amount"),
        .init(id: "32300", country: .canada, title: "Tuition amount", section: .credits, note: "Worked out on Schedule 11."),
        .init(id: "33099", country: .canada, title: "Medical expenses", section: .credits, note: "Only the part above 3% of net income (or the yearly cap) counts.", t1Field: "Page6.PartB.Line33099.Line_33099_Amount"),
        .init(id: "34900", country: .canada, title: "Donations and gifts", section: .credits, note: "Worked out on Schedule 9."),
        .init(id: "ON479", country: .canada, title: "Rent and property tax paid (Ontario)", section: .credits, note: "For the Ontario Trillium Benefit (ON-BEN application)."),
        .init(id: "43700", country: .canada, title: "Total income tax deducted", section: .payments, t1Field: "Page8.Step6-Continued.Line43700.Line_43700_Amount"),
        .init(id: "15000", country: .canada, title: "Total income", section: .totals),
        .init(id: "23600", country: .canada, title: "Net income", section: .totals),
        .init(id: "26000", country: .canada, title: "Taxable income", section: .totals),
        .init(id: "43500", country: .canada, title: "Total payable", section: .totals),
        .init(id: "48400", country: .canada, title: "Refund", section: .totals),
        .init(id: "48500", country: .canada, title: "Balance owing", section: .totals),
    ]

    static let us: [ReturnLine] = [
        .init(id: "1a", country: .us, title: "Wages (W-2 box 1)", section: .income),
        .init(id: "2a", country: .us, title: "Tax-exempt interest", section: .income),
        .init(id: "2b", country: .us, title: "Taxable interest", section: .income),
        .init(id: "3a", country: .us, title: "Qualified dividends", section: .income),
        .init(id: "3b", country: .us, title: "Ordinary dividends", section: .income),
        .init(id: "5b", country: .us, title: "Pensions and annuities, taxable", section: .income),
        .init(id: "6a", country: .us, title: "Social Security benefits", section: .income, note: "Only part may be taxable."),
        .init(id: "7", country: .us, title: "Capital gain or (loss)", section: .income, note: "Goes through Schedule D."),
        .init(id: "S1-1", country: .us, title: "Taxable state tax refunds", section: .income),
        .init(id: "S1-3", country: .us, title: "Business income (Schedule C)", section: .income, note: "Needs Schedule C with your expenses."),
        .init(id: "S1-5", country: .us, title: "Rental income (Schedule E)", section: .income),
        .init(id: "S1-7", country: .us, title: "Unemployment compensation", section: .income),
        .init(id: "S1-8z", country: .us, title: "Other income", section: .income),
        .init(id: "S1-21", country: .us, title: "Student loan interest deduction", section: .deductions, note: "Capped and phased out by income."),
        .init(id: "A-8a", country: .us, title: "Home mortgage interest", section: .deductions, note: "Only if you itemize (Schedule A)."),
        .init(id: "8863", country: .us, title: "Education credits (Form 8863)", section: .credits),
        .init(id: "25a", country: .us, title: "Federal tax withheld from W-2s", section: .payments),
        .init(id: "25b", country: .us, title: "Federal tax withheld from 1099s", section: .payments),
        .init(id: "9", country: .us, title: "Total income", section: .totals),
        .init(id: "11", country: .us, title: "Adjusted gross income", section: .totals),
        .init(id: "15", country: .us, title: "Taxable income", section: .totals),
        .init(id: "24", country: .us, title: "Total tax", section: .totals),
        .init(id: "33", country: .us, title: "Total payments", section: .totals),
        .init(id: "34", country: .us, title: "Overpaid (refund)", section: .totals),
        .init(id: "37", country: .us, title: "Amount you owe", section: .totals),
    ]

    static func lines(_ c: Country) -> [ReturnLine] { c == .canada ? canada : us }
}

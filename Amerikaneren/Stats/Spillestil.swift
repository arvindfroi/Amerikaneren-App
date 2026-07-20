import Foundation

/// Vurderer om en spiller byr optimalt, målt med de samme poeng-payoffene
/// MesterAI optimaliserer mot (tallbud n: ±2n/±n, Amerikaner ±50/±25,
/// solo ±100). Uten kortinformasjon (fysiske partier) kan ingen si om et
/// ENKELT bud var riktig – men over mange runder avslører resultatene
/// kalibreringen:
///
/// - **Margin**: laget tok X stikk med bud n. Var marginen stor og budet
///   holdt, VET vi i etterpåklokskap at et høyere bud også hadde holdt –
///   og nøyaktig hvor mange poeng som ble lagt igjen (3 per stikk:
///   2 til budgiver + 1 til makker).
/// - **Klaringsrate**: MesterAI, som simulerer tusenvis av verdener per
///   bud, lander målt på ~89 % klarte kontrakter med liten margin.
///   Ligger en spiller langt over med stor margin, byr de for lavt;
///   langt under, byr de for høyt. Referansesonen er 80–90 %.
struct Budanalyse {
    enum Dom: String {
        case forLiteData = "For lite data"
        case forForsiktig = "Byr for lavt"
        case balansert = "Godt kalibrert"
        case forAggressiv = "Byr for høyt"
    }

    /// MesterAI-referansen: målt klaringsrate for søkeboten som budgiver
    /// (68/76 kontrakter i benchmark, se docs/AI.md).
    static let mesterKlaringsrate = 0.89
    static let referansesone = 0.80...0.90

    var budGitt = 0              // alle budrunder som budgiver
    var budKlart = 0
    var tallbud = 0              // kun tallbud (margin gir bare mening der)
    var tallbudKlart = 0
    var sumMarginKlart = 0       // lagStikk − bud i klarte tallbudrunder
    var poengLagtIgjen = 0       // 3 × margin i klarte runder (etterpåklokskap)
    var poengTaptPåRøk = 0       // 3 × bud per røket tallbud
    var poengSomBudgiver = 0     // faktisk sum poengendring i budrundene
    var amerikanere = 0
    var amerikanereKlart = 0
    var soloer = 0
    var soloerKlart = 0

    var klaringsrate: Double { budGitt == 0 ? 0 : Double(budKlart) / Double(budGitt) }
    var snittMarginVedKlart: Double {
        tallbudKlart == 0 ? 0 : Double(sumMarginKlart) / Double(tallbudKlart)
    }
    var poengPerBudrunde: Double {
        budGitt == 0 ? 0 : Double(poengSomBudgiver) / Double(budGitt)
    }

    var dom: Dom {
        if budGitt < 8 { return .forLiteData }
        if klaringsrate < 0.55 { return .forAggressiv }
        if klaringsrate > Self.referansesone.upperBound && snittMarginVedKlart >= 1.3 {
            return .forForsiktig
        }
        return .balansert
    }

    var råd: String {
        switch dom {
        case .forLiteData:
            return "Spill flere runder som budgiver, så kalibrerer vi deg."
        case .forForsiktig:
            return "Du klarer \(Int(klaringsrate * 100)) % av budene med "
                + String(format: "%.1f", snittMarginVedKlart)
                + " stikk til overs – ca. \(poengLagtIgjen) poeng ligger igjen "
                + "på bordet. Prøv ett hakk høyere. (MesterAI ligger på ~89 %.)"
        case .forAggressiv:
            return "Bare \(Int(klaringsrate * 100)) % av budene holder – røkne "
                + "bud har kostet \(poengTaptPåRøk) poeng. Ta ett hakk ned. "
                + "(MesterAI ligger på ~89 %.)"
        case .balansert:
            return "\(Int(klaringsrate * 100)) % klaring med "
                + String(format: "%.1f", snittMarginVedKlart)
                + " i snittmargin – du er i MesterAI-sonen (80–90 %)."
        }
    }

    /// Beregner budanalysen for én deltaker-id fra rå partidata –
    /// på tvers av companion, offline og online.
    static func beregn(for deltakerId: String, fra partier: [MatchRecord]) -> Budanalyse {
        var a = Budanalyse()
        for parti in partier {
            let n = parti.deltakere.count
            for runde in parti.runder where runde.budgiverId == deltakerId {
                a.budGitt += 1
                if runde.klarte { a.budKlart += 1 }
                a.poengSomBudgiver += runde.poengEndring[deltakerId] ?? 0
                if runde.erSoloMelding {
                    a.soloer += 1
                    if runde.klarte { a.soloerKlart += 1 }
                } else if runde.erAmerikanerMelding {
                    a.amerikanere += 1
                    if runde.klarte { a.amerikanereKlart += 1 }
                } else {
                    a.tallbud += 1
                    if runde.klarte {
                        a.tallbudKlart += 1
                        let margin = max(0, runde.lagStikk(antallSpillere: n) - runde.bud)
                        a.sumMarginKlart += margin
                        a.poengLagtIgjen += 3 * margin
                    } else {
                        a.poengTaptPåRøk += 3 * runde.bud
                    }
                }
            }
        }
        return a
    }
}

/// Statistikk for et makkerpar: hvem lykkes sammen? Beregnes fra rå
/// partidata på tvers av alle modi, med uordnet par-id så «Ola med Kari»
/// og «Kari med Ola» telles sammen.
struct Makkerpar: Identifiable {
    var id: String               // "minsteId|størsteId"
    var idA: String
    var idB: String
    var navnA: String
    var navnB: String
    var runderSammen = 0
    var klart = 0
    var lagPoengSum = 0          // poengendring til budgiver + makker samlet

    var klaringsrate: Double { runderSammen == 0 ? 0 : Double(klart) / Double(runderSammen) }
    var poengPerRunde: Double { runderSammen == 0 ? 0 : Double(lagPoengSum) / Double(runderSammen) }
    var beskrivelse: String { "\(navnA) + \(navnB)" }

    static func beregn(fra partier: [MatchRecord]) -> [Makkerpar] {
        var tabell: [String: Makkerpar] = [:]
        for parti in partier {
            let navn = Dictionary(uniqueKeysWithValues: parti.deltakere.map { ($0.id, $0.navn) })
            for runde in parti.runder {
                guard let makkerId = runde.makkerId else { continue }
                let a = min(runde.budgiverId, makkerId)
                let b = max(runde.budgiverId, makkerId)
                var par = tabell["\(a)|\(b)"] ?? Makkerpar(
                    id: "\(a)|\(b)", idA: a, idB: b,
                    navnA: navn[a] ?? a, navnB: navn[b] ?? b
                )
                par.runderSammen += 1
                if runde.klarte { par.klart += 1 }
                par.lagPoengSum += (runde.poengEndring[runde.budgiverId] ?? 0)
                    + (runde.poengEndring[makkerId] ?? 0)
                tabell[par.id] = par
            }
        }
        return tabell.values.sorted { $0.runderSammen > $1.runderSammen }
    }
}

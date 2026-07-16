import Foundation

enum MatchMode: String, Codable, CaseIterable {
    case offline = "Mot maskinen"
    case online = "Online"
    case ranked = "Ranked"
    case companion = "Companion"
    case kampanje = "Kampanje"
}

/// Én deltaker i et registrert parti. CPU-er har opponentId satt.
struct MatchParticipant: Codable, Hashable, Identifiable {
    var id: String              // "meg", opponentId, eller companion-navn
    var navn: String
    var erMeg: Bool
    var opponentId: String?
    var sluttPoeng: Int
    var vantPartiet: Bool
}

/// Én budrunde i et parti – grunnlaget for detaljert statistikk.
struct RoundRecord: Codable, Hashable {
    var budgiverId: String
    var makkerId: String?
    var bud: Int                 // 1000 = Amerikaner-melding
    var trumf: String?
    var klarte: Bool
    var stikk: [String: Int]     // deltaker-id -> stikk
    var poengEndring: [String: Int]

    var erAmerikanerMelding: Bool { bud >= 1000 }
}

/// Et fullført parti.
struct MatchRecord: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var dato: Date = Date()
    var mode: MatchMode
    var deltakere: [MatchParticipant]
    var runder: [RoundRecord]
    var varighetSekunder: Int = 0
    var kampanjeStageId: String? = nil
    /// Ratingendring hvis partiet var ranked.
    var eloDelta: Int? = nil

    var vinner: MatchParticipant? { deltakere.first { $0.vantPartiet } }
    var jegVant: Bool { vinner?.erMeg == true }
}

/// Aggregert statistikk, beregnet fra alle MatchRecords.
struct AggregatedStats {
    var antallPartier = 0
    var seire = 0
    var antallRunder = 0
    var budGitt = 0
    var budKlart = 0
    var sumBudStørrelse = 0
    var amerikanerMeldinger = 0
    var amerikanerKlart = 0
    var totaleStikk = 0
    var poengSum = 0
    var besteScore = Int.min
    var lengsteSeiersrekke = 0
    var nåværendeRekke = 0
    var partierPerModus: [MatchMode: Int] = [:]
    var trumfValg: [String: Int] = [:]   // trumffarge -> antall ganger valgt som budgiver

    var seiersprosent: Double { antallPartier == 0 ? 0 : Double(seire) / Double(antallPartier) * 100 }
    var budTreffprosent: Double { budGitt == 0 ? 0 : Double(budKlart) / Double(budGitt) * 100 }
    var snittBud: Double { budGitt == 0 ? 0 : Double(sumBudStørrelse) / Double(budGitt) }
    var stikkPerRunde: Double { antallRunder == 0 ? 0 : Double(totaleStikk) / Double(antallRunder) }
    var snittPoeng: Double { antallPartier == 0 ? 0 : Double(poengSum) / Double(antallPartier) }
    var favorittTrumf: String? { trumfValg.max { $0.value < $1.value }?.key }

    static func beregn(for deltakerId: String, fra partier: [MatchRecord]) -> AggregatedStats {
        var s = AggregatedStats()
        // Eldste først, så seiersrekker beregnes riktig.
        for parti in partier.sorted(by: { $0.dato < $1.dato }) {
            guard let deltaker = parti.deltakere.first(where: { $0.id == deltakerId }) else { continue }
            s.antallPartier += 1
            s.partierPerModus[parti.mode, default: 0] += 1
            s.poengSum += deltaker.sluttPoeng
            s.besteScore = max(s.besteScore, deltaker.sluttPoeng)
            if deltaker.vantPartiet {
                s.seire += 1
                s.nåværendeRekke += 1
                s.lengsteSeiersrekke = max(s.lengsteSeiersrekke, s.nåværendeRekke)
            } else {
                s.nåværendeRekke = 0
            }
            for runde in parti.runder {
                s.antallRunder += 1
                s.totaleStikk += runde.stikk[deltakerId] ?? 0
                if runde.budgiverId == deltakerId {
                    s.budGitt += 1
                    if runde.klarte { s.budKlart += 1 }
                    if let trumf = runde.trumf { s.trumfValg[trumf, default: 0] += 1 }
                    if runde.erAmerikanerMelding {
                        s.amerikanerMeldinger += 1
                        if runde.klarte { s.amerikanerKlart += 1 }
                        s.sumBudStørrelse += 13
                    } else {
                        s.sumBudStørrelse += runde.bud
                    }
                }
            }
        }
        return s
    }
}

/// Head-to-head mellom meg og én bestemt motstander.
struct HeadToHead: Identifiable {
    var id: String { motstanderId }
    var motstanderId: String
    var motstanderNavn: String
    var opponent: Opponent?     // satt hvis CPU-figur

    var partier = 0
    var mineSeire = 0
    var deresSeire = 0
    var minPoengSum = 0
    var deresPoengSum = 0
    var sisteFem: [Bool] = []   // true = jeg vant
    var størsteSeierMargin = Int.min
    var sisteMøte: Date?
    var budDuellMine = 0        // budrunder jeg vant budet i disse partiene
    var budDuellDeres = 0

    var minSnittMargin: Double {
        partier == 0 ? 0 : Double(minPoengSum - deresPoengSum) / Double(partier)
    }

    static func beregn(fra partier: [MatchRecord], megId: String = "meg") -> [HeadToHead] {
        var tabell: [String: HeadToHead] = [:]
        for parti in partier.sorted(by: { $0.dato < $1.dato }) {
            guard let meg = parti.deltakere.first(where: { $0.id == megId }) else { continue }
            for motstander in parti.deltakere where !motstander.erMeg {
                var h2h = tabell[motstander.id] ?? HeadToHead(
                    motstanderId: motstander.id,
                    motstanderNavn: motstander.navn,
                    opponent: motstander.opponentId.flatMap { OpponentRoster.medId($0) }
                )
                h2h.partier += 1
                if meg.vantPartiet { h2h.mineSeire += 1 }
                if motstander.vantPartiet { h2h.deresSeire += 1 }
                h2h.minPoengSum += meg.sluttPoeng
                h2h.deresPoengSum += motstander.sluttPoeng
                h2h.sisteFem.append(meg.vantPartiet)
                if h2h.sisteFem.count > 5 { h2h.sisteFem.removeFirst() }
                h2h.størsteSeierMargin = max(h2h.størsteSeierMargin, meg.sluttPoeng - motstander.sluttPoeng)
                h2h.sisteMøte = parti.dato
                for runde in parti.runder {
                    if runde.budgiverId == megId { h2h.budDuellMine += 1 }
                    if runde.budgiverId == motstander.id { h2h.budDuellDeres += 1 }
                }
                tabell[motstander.id] = h2h
            }
        }
        return tabell.values.sorted { $0.partier > $1.partier }
    }
}

import Foundation
import SwiftUI

/// Poengføringslogikk for companion-modus.
@MainActor
final class CompanionViewModel: ObservableObject {
    struct FørtRunde: Codable {
        var budgiver: Int
        var makker: Int?
        var bud: Int            // 1000 = Amerikaner
        var klarte: Bool
        var stikk: [Int]
        var poengEndring: [Int]

        func beskrivelse(spillere: [String]) -> String {
            let budTekst = bud >= 1000 ? "Amerikaner" : "\(bud) stikk"
            var tekst = "\(spillere[budgiver]): \(budTekst)"
            if let makker { tekst += " (m/ \(spillere[makker]))" }
            return tekst
        }
    }

    @Published var navneliste: [String] = ["", "", "", ""]
    @Published var mittNavn: String = "Du" {
        didSet { if navneliste[0].isEmpty { navneliste[0] = mittNavn } }
    }
    @Published var målPoeng = 52

    @Published var partiPågår = false
    @Published private(set) var spillere: [String] = []
    @Published private(set) var poeng: [Int] = []
    @Published private(set) var runder: [FørtRunde] = []

    // Skjema for gjeldende runde
    @Published var budgiver = 0
    @Published var makker = -1
    @Published var bud = 5
    @Published var erAmerikaner = false
    @Published var klarte = true
    @Published var stikk: [Int] = []

    private var startTid = Date()

    var kanStarte: Bool {
        let navn = navneliste.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return navn.count >= 3 && Set(navn).count == navn.count
    }

    var kortPerSpiller: Int {
        spillere.isEmpty ? 13 : 52 / spillere.count
    }

    var sortert: [Int] {
        spillere.indices.sorted { poeng[$0] > poeng[$1] }
    }

    var ferdig: Bool {
        poeng.contains { $0 >= målPoeng }
    }

    func startParti() {
        spillere = navneliste
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        poeng = Array(repeating: 0, count: spillere.count)
        stikk = Array(repeating: 0, count: spillere.count)
        runder = []
        budgiver = 0
        makker = -1
        startTid = Date()
        partiPågår = true
    }

    func førRunde() {
        var endring = Array(repeating: 0, count: spillere.count)
        let budVerdi = erAmerikaner ? 1000 : bud
        let makkerIndex = erAmerikaner || makker == budgiver ? nil : (makker >= 0 ? makker : nil)

        if erAmerikaner {
            endring[budgiver] = klarte ? målPoeng : -målPoeng
        } else {
            let lagPoeng = klarte ? bud : -bud
            endring[budgiver] = lagPoeng
            if let makkerIndex { endring[makkerIndex] = lagPoeng }
        }
        for i in spillere.indices where i != budgiver && i != makkerIndex {
            endring[i] += stikk[i]
        }
        for i in spillere.indices { poeng[i] += endring[i] }

        runder.append(FørtRunde(
            budgiver: budgiver, makker: makkerIndex, bud: budVerdi,
            klarte: klarte, stikk: stikk, poengEndring: endring
        ))

        // Nullstill skjemaet til neste runde.
        stikk = Array(repeating: 0, count: spillere.count)
        budgiver = (budgiver + 1) % spillere.count
        makker = -1
        erAmerikaner = false
        klarte = true
    }

    func avbryt() {
        partiPågår = false
        runder = []
    }

    /// Id-er: «meg» for spiller 0, companion-navn for resten – slik at
    /// H2H-statistikken også fungerer for vennene dine.
    func lagMatchRecord() -> MatchRecord {
        let ider = spillere.indices.map { $0 == 0 ? "meg" : "companion-\(spillere[$0].lowercased())" }
        let vinnerIndex = sortert.first
        let deltakere = spillere.indices.map { i in
            MatchParticipant(
                id: ider[i], navn: spillere[i], erMeg: i == 0, opponentId: nil,
                sluttPoeng: poeng[i], vantPartiet: i == vinnerIndex
            )
        }
        let rundeRecords = runder.map { runde in
            RoundRecord(
                budgiverId: ider[runde.budgiver],
                makkerId: runde.makker.map { ider[$0] },
                bud: runde.bud,
                trumf: nil,
                klarte: runde.klarte,
                stikk: Dictionary(uniqueKeysWithValues: zip(ider, runde.stikk)),
                poengEndring: Dictionary(uniqueKeysWithValues: zip(ider, runde.poengEndring))
            )
        }
        return MatchRecord(
            mode: .companion, deltakere: deltakere, runder: rundeRecords,
            varighetSekunder: Int(Date().timeIntervalSince(startTid))
        )
    }
}

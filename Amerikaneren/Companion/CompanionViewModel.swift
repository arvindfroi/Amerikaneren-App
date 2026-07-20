import Foundation
import SwiftUI

/// Skjematilstand for companion-modus. Selve poengføringen bor i den
/// UI-frie `CompanionParti` (delt med kommandolinjeverktøyet og testene);
/// view-modellen holder skjemaet og kobler resultatet til statistikken.
@MainActor
final class CompanionViewModel: ObservableObject {
    typealias FørtRunde = CompanionParti.FørtRunde

    @Published var navneliste: [String] = ["", "", "", ""]
    @Published var mittNavn: String = "Du" {
        didSet { if navneliste[0].isEmpty { navneliste[0] = mittNavn } }
    }
    @Published var målPoeng = 100

    @Published var partiPågår = false
    @Published private(set) var parti: CompanionParti?

    // Skjema for gjeldende runde
    @Published var budgiver = 0
    @Published var makker = -1
    @Published var bud = 5
    @Published var erAmerikaner = false
    @Published var erSolo = false
    @Published var klarte = true
    @Published var stikk: [Int] = []

    private var startTid = Date()

    var spillere: [String] { parti?.spillere ?? [] }
    var poeng: [Int] { parti?.poeng ?? [] }
    var runder: [FørtRunde] { parti?.runder ?? [] }
    var sortert: [Int] { parti?.sortert ?? [] }
    var ferdig: Bool { parti?.ferdig ?? false }
    var kortPerSpiller: Int { parti?.kortPerSpiller ?? 13 }

    var kanStarte: Bool {
        CompanionParti.gyldigeSpillere(navneliste) != nil
    }

    func startParti() {
        guard let navn = CompanionParti.gyldigeSpillere(navneliste) else { return }
        parti = CompanionParti(spillere: navn, målPoeng: målPoeng)
        stikk = Array(repeating: 0, count: navn.count)
        budgiver = 0
        makker = -1
        startTid = Date()
        partiPågår = true
    }

    func førRunde() {
        guard parti != nil else { return }
        parti?.førRunde(
            budgiver: budgiver, makker: makker >= 0 ? makker : nil, bud: bud,
            erAmerikaner: erAmerikaner, erSolo: erSolo,
            klarte: klarte, stikk: stikk
        )

        // Nullstill skjemaet til neste runde.
        stikk = Array(repeating: 0, count: spillere.count)
        budgiver = (budgiver + 1) % spillere.count
        makker = -1
        erAmerikaner = false
        erSolo = false
        klarte = true
    }

    func avbryt() {
        partiPågår = false
        parti = nil
    }

    /// Id-er: «meg» for spiller 0, companion-navn for resten – slik at
    /// H2H-statistikken også fungerer for vennene dine.
    func lagMatchRecord() -> MatchRecord {
        let spillere = self.spillere
        let poeng = self.poeng
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

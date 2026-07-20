import Foundation
import SwiftUI

/// Poengføringslogikk for companion-modus – appen som verktøy ved siden av
/// fysisk spill. Designmål: minst mulig interaksjon. Per runde registreres
/// bare budvinner, bud, makker og motstandernes stikk; om laget klarte
/// budet regnes ut automatisk (lagets stikk = totalen minus motstandernes).
///
/// Partiet lagres fortløpende til disk, så appen kan lukkes og åpnes igjen
/// midt i et fysisk parti uten at noe går tapt.
@MainActor
final class CompanionViewModel: ObservableObject {
    /// Hva slags bud som vant budrunden.
    enum Budtype: String, CaseIterable, Identifiable {
        case vanlig, amerikaner, solo
        var id: String { rawValue }
        var navn: String {
            switch self {
            case .vanlig: return "Vanlig bud"
            case .amerikaner: return "Amerikaner"
            case .solo: return "Solo"
            }
        }
        /// Samme rangkoding som motoren (BidAction.rang) i lagrede runder.
        var budVerdi: Int? {
            switch self {
            case .vanlig: return nil
            case .amerikaner: return 1000
            case .solo: return 2000
            }
        }
    }

    struct FørtRunde: Codable {
        var budgiver: Int
        var makker: Int?
        var bud: Int            // 1000 = Amerikaner, 2000 = Solo-amerikaner
        var klarte: Bool
        var stikk: [Int]
        var poengEndring: [Int]

        func beskrivelse(spillere: [String]) -> String {
            let budTekst = bud >= 2000 ? "Solo-amerikaner"
                : bud >= 1000 ? "Amerikaner" : "\(bud) stikk"
            var tekst = "\(spillere[budgiver]): \(budTekst)"
            if let makker { tekst += " (m/ \(spillere[makker]))" }
            return tekst
        }
    }

    /// Én rad i oppsettskjemaet: navn + eventuell kobling til en bruker.
    struct Oppføring: Identifiable {
        var id = UUID()
        var navn = ""
        /// Game Center-id valgt i oppsettet – kobles til spillerprofilen
        /// når partiet starter.
        var gameCenterId: String? = nil
    }

    // MARK: - Oppsett

    @Published var oppføringer: [Oppføring] = [Oppføring(), Oppføring(), Oppføring(), Oppføring()]
    @Published var mittNavn: String = "Du" {
        didSet { if oppføringer[0].navn.isEmpty || oppføringer[0].navn == oldValue { oppføringer[0].navn = mittNavn } }
    }
    /// true = spill til `målPoeng`; false = åpent parti (spill så lenge
    /// dere vil, avslutt og lagre når som helst).
    @Published var harMål = true
    @Published var målPoeng = 100

    // MARK: - Partitilstand

    @Published private(set) var partiPågår = false
    @Published private(set) var spillere: [String] = []
    @Published private(set) var spillerIder: [String] = []
    @Published private(set) var aktivtMål: Int?
    @Published private(set) var poeng: [Int] = []
    @Published private(set) var runder: [FørtRunde] = []

    // Skjema for gjeldende runde
    @Published var budgiver = 0
    @Published var makker = -1
    @Published var bud = 5
    @Published var budtype: Budtype = .vanlig
    @Published var motstanderStikk: [Int] = []

    /// Poengsatser – samme som motoren (GameRules).
    private let satser = GameRules()

    private var startTid = Date()
    private let lagringURL: URL?

    /// `lagringURL: nil` skrur av persistens (brukes i tester).
    init(lagringURL: URL? = CompanionViewModel.standardLagringURL) {
        self.lagringURL = lagringURL
        lastPågåendeParti()
    }

    nonisolated static var standardLagringURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("companion-parti.json")
    }

    // MARK: - Avledet tilstand

    var kanStarte: Bool {
        let navn = oppføringer.map { $0.navn.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return navn.count >= 3 && Set(navn.map { $0.lowercased() }).count == navn.count
    }

    /// Kort per spiller etter at byttekortene er lagt av – samme regler
    /// som motoren (GameRules): 4 spillere: 12 kort/4 byttekort; ellers
    /// resten av stokken som byttekort (17/1, 10/2, 8/4).
    var kortPerSpiller: Int {
        spillere.isEmpty ? 12 : GameRules(antallSpillere: spillere.count).kortPerSpiller
    }

    /// Antall stikk i én runde = antall kort per spiller.
    var totalStikk: Int {
        kortPerSpiller
    }

    /// Bare solo-amerikaneren spilles uten makker.
    var makkerIndex: Int? {
        budtype == .solo || makker == budgiver || makker < 0 ? nil : makker
    }

    /// Vanlige bud og amerikaner krever at en makker er valgt.
    var makkerValgt: Bool {
        budtype == .solo || makkerIndex != nil
    }

    /// Setene som ikke er på budgiverlaget denne runden.
    var motstandere: [Int] {
        spillere.indices.filter { $0 != budgiver && $0 != makkerIndex }
    }

    var motstandernesStikk: Int {
        motstandere.reduce(0) { $0 + motstanderStikk[$1] }
    }

    /// Budgiverlagets stikk – utledet, aldri tastet inn.
    var lagetsStikk: Int {
        totalStikk - motstandernesStikk
    }

    /// Om laget klarte målet sitt – regnes ut automatisk fra motstandernes
    /// stikk, så brukeren slipper å svare på det. Amerikaner-meldingene
    /// krever alle stikkene; vanlige bud krever minst budet.
    var klarte: Bool {
        budtype == .vanlig ? lagetsStikk >= bud : motstandernesStikk == 0
    }

    /// Stikkene kan ikke summere til mer enn det finnes stikk i runden.
    var stikkGyldige: Bool {
        motstandernesStikk <= totalStikk
    }

    /// Alt som må være på plass før runden kan føres.
    var kanFøreRunde: Bool {
        stikkGyldige && makkerValgt
    }

    var sortert: [Int] {
        spillere.indices.sorted { poeng[$0] > poeng[$1] }
    }

    var ferdig: Bool {
        guard let mål = aktivtMål else { return false }
        return poeng.contains { $0 >= mål }
    }

    /// Vinneren av partiet. Står flere likt (eller passerer målet i samme
    /// runde), vinner budgiversiden fra siste runde – vanlig husregel.
    var vinnerIndex: Int? {
        guard let beste = poeng.max() else { return nil }
        let kandidater = spillere.indices.filter { poeng[$0] == beste }
        if kandidater.count > 1, let siste = runder.last {
            let lag = [siste.budgiver, siste.makker].compactMap { $0 }
            if let påLaget = kandidater.first(where: { lag.contains($0) }) { return påLaget }
        }
        return kandidater.first
    }

    // MARK: - Oppsett

    func leggTilSpiller() {
        guard oppføringer.count < 6 else { return }
        oppføringer.append(Oppføring())
    }

    func fjernSpiller(at index: Int) {
        guard oppføringer.count > 3, index > 0 else { return }
        oppføringer.remove(at: index)
    }

    /// Starter partiet. `appState` løser navnene til registrerte
    /// spillerprofiler (og lagrer koblinger til brukere); nil i tester.
    func startParti(appState: AppState? = nil) {
        let aktive = oppføringer
            .map { Oppføring(navn: $0.navn.trimmingCharacters(in: .whitespaces), gameCenterId: $0.gameCenterId) }
            .filter { !$0.navn.isEmpty }
        guard aktive.count >= 3 else { return }

        spillere = aktive.map(\.navn)
        spillerIder = aktive.enumerated().map { i, oppføring in
            if i == 0 { return "meg" }
            if let appState {
                let spiller = appState.finnEllerOpprettSpiller(navn: oppføring.navn)
                if let gcId = oppføring.gameCenterId, spiller.gameCenterId == nil {
                    appState.koblSpiller(id: spiller.id, tilGameCenterId: gcId)
                    return "online-\(gcId)"
                }
                return spiller.deltakerId
            }
            return oppføring.gameCenterId.map { "online-\($0)" }
                ?? RegistrertSpiller.lagId(for: oppføring.navn)
        }
        aktivtMål = harMål ? målPoeng : nil
        poeng = Array(repeating: 0, count: spillere.count)
        motstanderStikk = Array(repeating: 0, count: spillere.count)
        runder = []
        budgiver = 0
        makker = -1
        bud = 5
        budtype = .vanlig
        startTid = Date()
        partiPågår = true
        lagrePågåendeParti()
    }

    // MARK: - Runder

    func førRunde() {
        guard kanFøreRunde else { return }
        var endring = Array(repeating: 0, count: spillere.count)
        let lag = makkerIndex
        let klarteBudet = klarte
        let fortegn = klarteBudet ? 1 : -1

        // Budgiveren får alltid dobbelt av makkeren – i pluss som i minus.
        switch budtype {
        case .solo:
            endring[budgiver] = fortegn * satser.soloAmerikanerPoeng
        case .amerikaner:
            endring[budgiver] = fortegn * satser.amerikanerPoeng
            if let lag { endring[lag] = fortegn * satser.amerikanerPoeng / 2 }
        case .vanlig:
            endring[budgiver] = fortegn * bud * satser.budgiverFaktor
            if let lag { endring[lag] = fortegn * bud }
        }
        for i in motstandere {
            endring[i] += motstanderStikk[i]
        }
        for i in spillere.indices { poeng[i] += endring[i] }

        var stikkRad = spillere.indices.map { motstandere.contains($0) ? motstanderStikk[$0] : 0 }
        if budtype == .solo && klarteBudet { stikkRad[budgiver] = totalStikk }

        runder.append(FørtRunde(
            budgiver: budgiver, makker: lag, bud: budtype.budVerdi ?? bud,
            klarte: klarteBudet, stikk: stikkRad, poengEndring: endring
        ))

        // Nullstill skjemaet til neste runde.
        motstanderStikk = Array(repeating: 0, count: spillere.count)
        budgiver = (budgiver + 1) % spillere.count
        makker = -1
        bud = 5
        budtype = .vanlig
        lagrePågåendeParti()
    }

    /// Angrer siste førte runde – lett å taste feil rundt et fysisk bord.
    func angreSisteRunde() {
        guard let siste = runder.popLast() else { return }
        for i in spillere.indices { poeng[i] -= siste.poengEndring[i] }
        budgiver = siste.budgiver
        makker = siste.makker ?? -1
        budtype = siste.bud >= 2000 ? .solo : siste.bud >= 1000 ? .amerikaner : .vanlig
        bud = siste.bud >= 1000 ? 5 : siste.bud
        motstanderStikk = spillere.indices.map { i in
            i == siste.budgiver || i == siste.makker ? 0 : siste.stikk[i]
        }
        lagrePågåendeParti()
    }

    // MARK: - Avslutning

    func avbryt() {
        partiPågår = false
        runder = []
        slettPågåendeParti()
    }

    /// Bygger og registrerer MatchRecord, og rydder bort det pågående
    /// partiet. Brukes både når målet er nådd og når et åpent parti
    /// avsluttes manuelt.
    func avsluttOgLagre(i appState: AppState) {
        appState.registrerParti(lagMatchRecord())
        partiPågår = false
        runder = []
        slettPågåendeParti()
    }

    func lagMatchRecord() -> MatchRecord {
        let vinner = vinnerIndex
        let deltakere = spillere.indices.map { i in
            MatchParticipant(
                id: spillerIder[i], navn: spillere[i], erMeg: i == 0, opponentId: nil,
                sluttPoeng: poeng[i], vantPartiet: i == vinner
            )
        }
        let rundeRecords = runder.map { runde in
            RoundRecord(
                budgiverId: spillerIder[runde.budgiver],
                makkerId: runde.makker.map { spillerIder[$0] },
                bud: runde.bud,
                trumf: nil,
                klarte: runde.klarte,
                stikk: Dictionary(uniqueKeysWithValues: zip(spillerIder, runde.stikk)),
                poengEndring: Dictionary(uniqueKeysWithValues: zip(spillerIder, runde.poengEndring))
            )
        }
        return MatchRecord(
            mode: .companion, deltakere: deltakere, runder: rundeRecords,
            varighetSekunder: Int(Date().timeIntervalSince(startTid))
        )
    }

    // MARK: - Persistens av pågående parti

    private struct LagretParti: Codable {
        var spillere: [String]
        var spillerIder: [String]
        var aktivtMål: Int?
        var poeng: [Int]
        var runder: [FørtRunde]
        var budgiver: Int
        var startTid: Date
    }

    private func lagrePågåendeParti() {
        guard let lagringURL else { return }
        let lagret = LagretParti(
            spillere: spillere, spillerIder: spillerIder, aktivtMål: aktivtMål,
            poeng: poeng, runder: runder, budgiver: budgiver, startTid: startTid
        )
        do {
            try JSONEncoder().encode(lagret).write(to: lagringURL, options: .atomic)
        } catch {
            print("Kunne ikke lagre pågående companion-parti: \(error)")
        }
    }

    private func lastPågåendeParti() {
        guard let lagringURL,
              let data = try? Data(contentsOf: lagringURL),
              let lagret = try? JSONDecoder().decode(LagretParti.self, from: data),
              lagret.spillere.count >= 3,
              lagret.spillere.count == lagret.poeng.count else { return }
        spillere = lagret.spillere
        spillerIder = lagret.spillerIder
        aktivtMål = lagret.aktivtMål
        poeng = lagret.poeng
        runder = lagret.runder
        budgiver = min(lagret.budgiver, spillere.count - 1)
        startTid = lagret.startTid
        motstanderStikk = Array(repeating: 0, count: spillere.count)
        makker = -1
        bud = 5
        budtype = .vanlig
        partiPågår = true
    }

    private func slettPågåendeParti() {
        guard let lagringURL else { return }
        try? FileManager.default.removeItem(at: lagringURL)
    }
}

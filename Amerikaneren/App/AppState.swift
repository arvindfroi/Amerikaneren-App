import Foundation
import SwiftUI

/// Global app-tilstand med enkel JSON-persistens i Documents-mappen.
@MainActor
final class AppState: ObservableObject {
    @Published var harFullførtOnboarding: Bool {
        didSet { UserDefaults.standard.set(harFullførtOnboarding, forKey: "onboardingFerdig") }
    }
    @Published var spillerNavn: String {
        didSet { UserDefaults.standard.set(spillerNavn, forKey: "spillerNavn") }
    }
    @Published private(set) var partier: [MatchRecord] = []
    /// Spillerprofiler for folk du spiller fysisk med (companion-modus).
    @Published private(set) var registrerteSpillere: [RegistrertSpiller] = []
    @Published var kampanje: CampaignProgress = CampaignProgress() {
        didSet { lagre(kampanje, til: "kampanje.json") }
    }

    // Innstillinger
    @Published var lydPå: Bool {
        didSet { UserDefaults.standard.set(lydPå, forKey: "lydPå") }
    }
    @Published var haptikkPå: Bool {
        didSet { UserDefaults.standard.set(haptikkPå, forKey: "haptikkPå") }
    }
    /// Større kort i hånden – lettere å treffe og lese.
    @Published var storeKort: Bool {
        didSet { UserDefaults.standard.set(storeKort, forKey: "storeKort") }
    }
    /// Samtykke til å dele anonyme partiopptak (kort, bud og trekk – aldri
    /// navn) som treningsdata for AI-en. Av som standard; skrus den av
    /// igjen tømmes den lokale sendekøen.
    @Published var datadelingPå: Bool {
        didSet {
            UserDefaults.standard.set(datadelingPå, forKey: Innsamler.samtykkeNøkkel)
            if !datadelingPå { Innsamler.standard.tømKø() }
        }
    }

    // Ranked / Elo
    @Published private(set) var eloRating: Int {
        didSet { UserDefaults.standard.set(eloRating, forKey: "eloRating") }
    }
    @Published private(set) var eloHistorikk: [EloEntry] = []

    var rankTier: RankTier { RankTier.forRating(eloRating) }
    var antallRankedKamper: Int { eloHistorikk.count }

    init() {
        harFullførtOnboarding = UserDefaults.standard.bool(forKey: "onboardingFerdig")
        spillerNavn = UserDefaults.standard.string(forKey: "spillerNavn") ?? "Du"
        lydPå = UserDefaults.standard.object(forKey: "lydPå") as? Bool ?? true
        haptikkPå = UserDefaults.standard.object(forKey: "haptikkPå") as? Bool ?? true
        storeKort = UserDefaults.standard.object(forKey: "storeKort") as? Bool ?? false
        datadelingPå = UserDefaults.standard.bool(forKey: Innsamler.samtykkeNøkkel)
        eloRating = UserDefaults.standard.object(forKey: "eloRating") as? Int ?? EloCalculator.startRating
        partier = les([MatchRecord].self, fra: "partier.json") ?? []
        registrerteSpillere = les([RegistrertSpiller].self, fra: "spillere.json") ?? []
        kampanje = les(CampaignProgress.self, fra: "kampanje.json") ?? CampaignProgress()
        eloHistorikk = les([EloEntry].self, fra: "elo.json") ?? []
    }

    /// Registrerer resultatet av en ranked-kamp og oppdaterer ratingen.
    func brukEloResultat(delta: Int, plassering: Int) {
        eloRating = max(100, eloRating + delta)
        eloHistorikk.append(EloEntry(rating: eloRating, delta: delta, plassering: plassering))
        lagre(eloHistorikk, til: "elo.json")
    }

    func registrerParti(_ parti: MatchRecord) {
        partier.append(parti)
        lagre(partier, til: "partier.json")
    }

    func slettAlleData() {
        partier = []
        kampanje = CampaignProgress()
        registrerteSpillere = []
        lagre(partier, til: "partier.json")
        lagre(registrerteSpillere, til: "spillere.json")
    }

    // MARK: - Spillerregister (companion)

    /// Finner en registrert spiller på navn (uavhengig av store/små
    /// bokstaver), eller oppretter en ny profil om ingen finnes.
    func finnEllerOpprettSpiller(navn: String) -> RegistrertSpiller {
        let ryddet = navn.trimmingCharacters(in: .whitespaces)
        if let eksisterende = registrerteSpillere.first(where: {
            $0.navn.compare(ryddet, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            return eksisterende
        }
        let ny = RegistrertSpiller(id: RegistrertSpiller.lagId(for: ryddet), navn: ryddet)
        registrerteSpillere.append(ny)
        lagre(registrerteSpillere, til: "spillere.json")
        return ny
    }

    /// Kobler (eller frakobler, med nil) en registrert spiller til en
    /// Game Center-bruker, slik at companion- og online-partier mot samme
    /// person telles sammen.
    func koblSpiller(id: String, tilGameCenterId gcId: String?) {
        guard let i = registrerteSpillere.firstIndex(where: { $0.id == id }) else { return }
        registrerteSpillere[i].gameCenterId = gcId
        lagre(registrerteSpillere, til: "spillere.json")
    }

    /// Brukere vi kjenner fra online-partier – kandidater for kobling av
    /// companion-spillere til ekte kontoer.
    var kjenteOnlineBrukere: [(gameCenterId: String, navn: String)] {
        var sett = Set<String>()
        var resultat: [(gameCenterId: String, navn: String)] = []
        for parti in partier.sorted(by: { $0.dato > $1.dato }) {
            for deltaker in parti.deltakere where deltaker.id.hasPrefix("online-") {
                let gcId = String(deltaker.id.dropFirst("online-".count))
                if sett.insert(gcId).inserted {
                    resultat.append((gameCenterId: gcId, navn: deltaker.navn))
                }
            }
        }
        return resultat
    }

    var mineStats: AggregatedStats { AggregatedStats.beregn(for: "meg", fra: partier) }
    var headToHead: [HeadToHead] { HeadToHead.beregn(fra: partier) }

    // MARK: - Persistens

    private func url(for fil: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fil)
    }

    private func lagre<T: Encodable>(_ verdi: T, til fil: String) {
        do {
            let data = try JSONEncoder().encode(verdi)
            try data.write(to: url(for: fil), options: .atomic)
        } catch {
            print("Kunne ikke lagre \(fil): \(error)")
        }
    }

    private func les<T: Decodable>(_ type: T.Type, fra fil: String) -> T? {
        guard let data = try? Data(contentsOf: url(for: fil)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

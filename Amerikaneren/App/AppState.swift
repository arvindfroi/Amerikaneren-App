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
    @Published var kampanje: CampaignProgress = CampaignProgress() {
        didSet { lagre(kampanje, til: "kampanje.json") }
    }

    init() {
        harFullførtOnboarding = UserDefaults.standard.bool(forKey: "onboardingFerdig")
        spillerNavn = UserDefaults.standard.string(forKey: "spillerNavn") ?? "Du"
        partier = les([MatchRecord].self, fra: "partier.json") ?? []
        kampanje = les(CampaignProgress.self, fra: "kampanje.json") ?? CampaignProgress()
    }

    func registrerParti(_ parti: MatchRecord) {
        partier.append(parti)
        lagre(partier, til: "partier.json")
    }

    func slettAlleData() {
        partier = []
        kampanje = CampaignProgress()
        lagre(partier, til: "partier.json")
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

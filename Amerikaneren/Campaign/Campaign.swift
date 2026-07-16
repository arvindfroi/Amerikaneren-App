import Foundation

/// Et kampanjeoppdrag i Punch-Out-stil: en hovedmotstander, to «sparringpartnere»
/// ved bordet, og et scenario med spesialregler.
struct CampaignStage: Identifiable, Codable, Hashable {
    let id: String
    let hovedmotstanderId: String
    let scenarioTittel: String
    let scenarioTekst: String

    // Scenario-modifikatorer
    var motstanderStartPoeng: Int = 0     // hovedmotstanderen starter med forsprang
    var spillerStartPoeng: Int = 0
    var kravMinsteBud: Int? = nil          // du må vinne minst én budrunde med dette budet
    var målPoeng: Int = 52

    var hovedmotstander: Opponent {
        OpponentRoster.medId(hovedmotstanderId) ?? OpponentRoster.mester
    }
}

struct CampaignCircuit: Identifiable, Codable, Hashable {
    let id: String
    let navn: String
    let emoji: String
    let stages: [CampaignStage]
}

enum CampaignData {
    static let kretser: [CampaignCircuit] = [
        CampaignCircuit(
            id: "bronse", navn: "Bronseligaen", emoji: "🥉",
            stages: [
                CampaignStage(
                    id: "b1", hovedmotstanderId: "washington",
                    scenarioTittel: "Kirsebærtreet",
                    scenarioTekst: "Grunnleggeren tar imot deg med åpne kort og ærlige bud. Slå ham i et rent parti til 52."
                ),
                CampaignStage(
                    id: "b2", hovedmotstanderId: "franklin",
                    scenarioTittel: "Lyn og trumf",
                    scenarioTekst: "Franklin eksperimenterer vilt. Han starter med 8 poeng i kondensatoren – ta ham igjen!",
                    motstanderStartPoeng: 8
                ),
                CampaignStage(
                    id: "b3", hovedmotstanderId: "jefferson",
                    scenarioTittel: "Uavhengighetserklæringen",
                    scenarioTekst: "Bevis din egen uavhengighet: du må vinne minst én budrunde med bud på 7 eller mer for å ta kretsen.",
                    kravMinsteBud: 7
                )
            ]
        ),
        CampaignCircuit(
            id: "solv", navn: "Sølvligaen", emoji: "🥈",
            stages: [
                CampaignStage(
                    id: "s1", hovedmotstanderId: "lincoln",
                    scenarioTittel: "Et hus i strid",
                    scenarioTekst: "Lincoln splittes aldri fra makkeren sin. Du starter 5 poeng bak – samle laget ditt.",
                    motstanderStartPoeng: 5
                ),
                CampaignStage(
                    id: "s2", hovedmotstanderId: "roosevelt-t",
                    scenarioTittel: "Stormløpet",
                    scenarioTekst: "Teddy byr høyt hver eneste runde. Sprintpartiet går bare til 39 poeng – heng med!",
                    målPoeng: 39
                ),
                CampaignStage(
                    id: "s3", hovedmotstanderId: "roosevelt-fd",
                    scenarioTittel: "Den nye given",
                    scenarioTekst: "FDR starter med 10 poeng i depresjonshjelp. Vis at du ikke frykter noen ting.",
                    motstanderStartPoeng: 10
                )
            ]
        ),
        CampaignCircuit(
            id: "gull", navn: "Gulligaen", emoji: "🥇",
            stages: [
                CampaignStage(
                    id: "g1", hovedmotstanderId: "kennedy",
                    scenarioTittel: "Månekappløpet",
                    scenarioTekst: "Først til månen – altså 52. Kennedy elsker Amerikaner-meldinger. Ikke la ham lette."
                ),
                CampaignStage(
                    id: "g2", hovedmotstanderId: "reagan",
                    scenarioTittel: "Bløffmuren",
                    scenarioTekst: "Skuespilleren bløffer i annenhver budrunde. Du må vinne en budrunde med bud på 8+ for å avsløre ham.",
                    kravMinsteBud: 8
                ),
                CampaignStage(
                    id: "g3", hovedmotstanderId: "trump",
                    scenarioTittel: "Kunsten å by",
                    scenarioTekst: "Trumfmesteren byr enormt og melder Amerikaner i annenhver runde. Han starter med 10 poeng han sier han har bygget helt selv.",
                    motstanderStartPoeng: 10
                ),
                CampaignStage(
                    id: "g4", hovedmotstanderId: "eisenhower",
                    scenarioTittel: "D-dagen",
                    scenarioTekst: "Generalen har planlagt alt og starter med 12 poeng. Maratonpartiet går til 65.",
                    motstanderStartPoeng: 12, målPoeng: 65
                )
            ]
        ),
        CampaignCircuit(
            id: "tittel", navn: "Tittelkampen", emoji: "🏆",
            stages: [
                CampaignStage(
                    id: "t1", hovedmotstanderId: "onkelsam",
                    scenarioTittel: "Selveste Amerikaneren",
                    scenarioTekst: "Onkel Sam spiller feilfritt og starter med 15 poeng. Slå ham, og tittelen «Amerikaneren» er din for alltid.",
                    motstanderStartPoeng: 15
                )
            ]
        )
    ]

    static func stage(id: String) -> (CampaignCircuit, CampaignStage)? {
        for krets in kretser {
            if let stage = krets.stages.first(where: { $0.id == id }) {
                return (krets, stage)
            }
        }
        return nil
    }

    /// Sparringpartnere ved bordet: to andre figurer på lavere nivå.
    static func bordFor(stage: CampaignStage) -> [Opponent] {
        let hoved = stage.hovedmotstander
        let andre = OpponentRoster.alle
            .filter { $0.id != hoved.id && $0.id != OpponentRoster.mester.id }
            .shuffled()
            .prefix(2)
        return [hoved] + andre
    }
}

/// Fremdrift i kampanjen, lagres lokalt.
struct CampaignProgress: Codable {
    var fullførteStages: Set<String> = []
    var forsøk: [String: Int] = [:]

    func erLåstOpp(_ stage: CampaignStage, i krets: CampaignCircuit) -> Bool {
        // Første stage i en krets krever at forrige krets er fullført.
        let kretser = CampaignData.kretser
        guard let kretsIndex = kretser.firstIndex(of: krets),
              let stageIndex = krets.stages.firstIndex(of: stage) else { return false }
        if stageIndex > 0 {
            return fullførteStages.contains(krets.stages[stageIndex - 1].id)
        }
        if kretsIndex == 0 { return true }
        return kretser[kretsIndex - 1].stages.allSatisfy { fullførteStages.contains($0.id) }
    }

    var erMester: Bool {
        fullførteStages.contains("t1")
    }
}

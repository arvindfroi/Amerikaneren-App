import Foundation

/// Ett komplett rundeopptak: alt som trengs for å spille runden av på nytt,
/// trekk for trekk. Dette er råformatet for treningsdata – rått og lite,
/// slik at fremtidige trekkuttrekk kan regenereres uansett hvordan
/// nettets input-koding endrer seg.
struct Rundeopptak: Codable, Equatable {
    var hender: [[Card]]        // utdelte hender per sete, før talong-opptak
    var talon: [Card]
    var førsteBudgiver: Int
    var bud: [PlacedBid]        // hele budrunden i rekkefølge, inkl. pass
    var kastet: [Card]          // budvinnerens vrak (tomt uten byttekort)
    var trumf: Suit
    var ønsket: Card?           // nil kun ved solo uten etterlysning
    var spilte: [Card]          // alle kort i nøyaktig spilt rekkefølge
    var resultat: RoundResult

    /// Fanger runden som nettopp ble ferdig i motoren. Returnerer nil hvis
    /// motoren ikke står ved slutten av en ferdigspilt runde.
    init?(fra motor: GameEngine) {
        guard motor.phase == .rundeFerdig || motor.phase == .spillFerdig,
              let resultat = motor.sisteRunde,
              let trumf = motor.trumf,
              motor.hands.allSatisfy({ $0.isEmpty }) else { return nil }
        self.hender = motor.utdelteHender
        self.talon = motor.utdeltTalon
        self.førsteBudgiver = motor.førsteBudgiverIRunden
        self.bud = motor.bids
        self.kastet = motor.kastet
        self.trumf = trumf
        self.ønsket = motor.ønsketKort
        self.spilte = motor.spilteKort
        self.resultat = resultat
    }
}

/// Hvem som satt i setene – helt anonymt: bare om det var et menneske,
/// og hvilken CPU-styrke ellers. Aldri navn eller identiteter.
struct Seteinfo: Codable, Equatable {
    var menneske: Bool
    var cpuNivå: String?
}

/// Et helt parti klart for innsamling. `dag` er med vilje bare en dato
/// (ikke klokkeslett), og `installasjon` er en tilfeldig ID uten kobling
/// til navn, Game Center eller enhet.
struct Partiopptak: Codable, Equatable {
    static let gjeldendeVersjon = 1

    var id: UUID
    var versjon: Int
    var app: String
    var regler: GameRules
    var modus: String            // offline | kampanje | online
    var seter: [Seteinfo]
    var runder: [Rundeopptak]
    var sluttPoeng: [Int]
    var vinner: Int?
    var dag: String

    init(regler: GameRules, modus: String, seter: [Seteinfo],
         runder: [Rundeopptak], sluttPoeng: [Int], vinner: Int?) {
        self.id = UUID()
        self.versjon = Self.gjeldendeVersjon
        self.app = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        self.regler = regler
        self.modus = modus
        self.seter = seter
        self.runder = runder
        self.sluttPoeng = sluttPoeng
        self.vinner = vinner
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd"
        format.timeZone = TimeZone(identifier: "UTC")
        self.dag = format.string(from: Date())
    }
}

/// Ett valg tatt underveis i en avspilt runde. Avspillingen kaller tilbake
/// med motoren i tilstanden FØR valget – det er kroken treningsimporten
/// bruker til å hente ut (situasjon → fasit)-par.
enum Trekkvalg {
    case bud(sete: Int, valg: BidAction)
    case vrak(sete: Int, valg: [Card])
    case trumfvalg(sete: Int, trumf: Suit, ønsket: Card?)
    case spill(sete: Int, valg: Card)
}

enum Opptakfeil: Error, CustomStringConvertible {
    case ugyldigUtdeling
    case ulovligTrekk(String)
    case resultatAvvik

    var description: String {
        switch self {
        case .ugyldigUtdeling: return "utdelingen er ikke en gyldig kortstokk"
        case .ulovligTrekk(let hva): return "ulovlig trekk i opptaket: \(hva)"
        case .resultatAvvik: return "avspilt resultat avviker fra opptaket"
        }
    }
}

extension Rundeopptak {
    /// Spiller opptaket av i en fersk motor og verifiserer hvert eneste
    /// trekk mot reglene – og sluttresultatet mot det som ble lagret.
    /// Ugyldige eller tuklede opptak kastes dermed alltid ut før de kan
    /// bli treningsdata.
    @discardableResult
    func spillAv(regler: GameRules,
                 vedTrekk: ((GameEngine, Trekkvalg) -> Void)? = nil) throws -> GameEngine {
        // Utdelingen må være nøyaktig én full kortstokk.
        let alleKort = hender.flatMap { $0 } + talon
        guard alleKort.count == 52, Set(alleKort).count == 52,
              hender.count == regler.antallSpillere,
              hender.allSatisfy({ $0.count == regler.kortPerSpiller }),
              talon.count == regler.antallByttekort,
              (0..<regler.antallSpillere).contains(førsteBudgiver) else {
            throw Opptakfeil.ugyldigUtdeling
        }

        let motor = GameEngine(rules: regler)
        motor.startRunde(hender: hender, talon: talon, førsteBudgiver: førsteBudgiver)

        for melding in bud {
            guard melding.seat == motor.aktivBudgiver else {
                throw Opptakfeil.ulovligTrekk("bud fra sete \(melding.seat) utenfor tur")
            }
            vedTrekk?(motor, .bud(sete: melding.seat, valg: melding.action))
            guard motor.giBud(seat: melding.seat, action: melding.action) else {
                throw Opptakfeil.ulovligTrekk("bud \(melding.action.beskrivelse) fra sete \(melding.seat)")
            }
        }

        guard let budgiver = motor.budgiverSeat else {
            throw Opptakfeil.ulovligTrekk("budrunden endte uten vinner")
        }
        if regler.medByttekort {
            vedTrekk?(motor, .vrak(sete: budgiver, valg: kastet))
            guard motor.kastByttekort(kastet, seat: budgiver) else {
                throw Opptakfeil.ulovligTrekk("vrak \(kastet.map(\.kortSymbol))")
            }
        }
        vedTrekk?(motor, .trumfvalg(sete: budgiver, trumf: trumf, ønsket: ønsket))
        guard motor.velgTrumf(suit: trumf, ønsket: ønsket) else {
            throw Opptakfeil.ulovligTrekk("trumfvalg \(trumf.navn)")
        }

        for kort in spilte {
            let sete = motor.aktivSpiller
            vedTrekk?(motor, .spill(sete: sete, valg: kort))
            guard motor.spill(kort: kort, seat: sete) else {
                throw Opptakfeil.ulovligTrekk("kort \(kort.kortSymbol) fra sete \(sete)")
            }
        }

        guard motor.phase == .rundeFerdig || motor.phase == .spillFerdig,
              motor.sisteRunde == resultat else {
            throw Opptakfeil.resultatAvvik
        }
        return motor
    }
}

extension Partiopptak {
    /// Verifiserer hele partiet ved å spille av hver runde. Kaster ved
    /// første avvik.
    func verifiser() throws {
        for runde in runder {
            try runde.spillAv(regler: regler)
        }
    }
}

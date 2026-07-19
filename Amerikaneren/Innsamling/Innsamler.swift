import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Oppsett for innsamlingen. Endepunktet peker på ingest-backenden
/// (se Backend/README.md); appnøkkelen er en delt nøkkel som stopper
/// tilfeldig støy – selve datavernet ligger i at innholdet er anonymt.
struct InnsamlingKonfig {
    var endepunkt: URL?
    var appNøkkel: String
    var maksIKø: Int = 200
    var maksPerOpplasting: Int = 8

    /// Endepunktet settes når backenden (Backend/valtown) er deployet.
    /// Inntil da samles opptak kun i den lokale køen (avgrenset), og
    /// lastes opp automatisk så snart et endepunkt finnes.
    static let produksjon = InnsamlingKonfig(
        endepunkt: nil,
        appNøkkel: "amerikaneren-app-v1"
    )
}

/// Samler anonyme partiopptak til fremtidig trening – kun med samtykke.
///
/// Robusthet i klienten:
/// - Opptak verifiseres ved avspilling FØR de legges i kø; ugyldige kastes.
/// - Køen ligger som enkeltfiler på disk og overlever at appen drepes.
/// - Køen er avgrenset (`maksIKø`); eldste fil ryddes først.
/// - Opplasting skjer i småbatcher; nettverksfeil lar filene ligge til
///   neste forsøk, mens 4xx-svar («giftige» opptak backenden avviser)
///   sletter filene så køen aldri kiler seg fast.
/// - Uten samtykke lagres og sendes ingenting.
final class Innsamler {
    static let standard = Innsamler(konfig: .produksjon)

    static let samtykkeNøkkel = "datadelingPå"

    private let konfig: InnsamlingKonfig
    private let køMappe: URL
    private let filkø = DispatchQueue(label: "innsamler.kø")
    private var lasterOpp = false

    /// Testbar init: egen mappe og eget oppsett.
    init(konfig: InnsamlingKonfig, mappe: URL? = nil) {
        self.konfig = konfig
        if let mappe {
            self.køMappe = mappe
        } else {
            let støtte = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.køMappe = støtte.appendingPathComponent("Innsamling/kø", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: køMappe, withIntermediateDirectories: true)
    }

    var harSamtykke: Bool {
        UserDefaults.standard.bool(forKey: Self.samtykkeNøkkel)
    }

    /// Leverer et ferdig parti til køen og starter et opplastingsforsøk.
    /// Uten samtykke skjer ingenting. Ugyldige opptak forkastes stille –
    /// et opptak som ikke består sin egen avspilling er verdiløst som data.
    func leverParti(_ parti: Partiopptak, krevSamtykke: Bool = true) {
        if krevSamtykke && !harSamtykke { return }
        filkø.async { [self] in
            do {
                try parti.verifiser()
                let data = try JSONEncoder().encode(parti)
                let fil = køMappe.appendingPathComponent("\(parti.id.uuidString).json")
                try data.write(to: fil, options: .atomic)
                beskjærKø()
            } catch {
                // Forkast – aldri la et defekt opptak stoppe innsamlingen.
            }
            prøvOpplastingLåst()
        }
    }

    /// Kalles ved appstart/forgrunn: send det som måtte ligge i kø.
    func prøvOpplasting() {
        guard harSamtykke else { return }
        filkø.async { [self] in prøvOpplastingLåst() }
    }

    /// Sletter hele køen – brukes når samtykket trekkes tilbake.
    func tømKø() {
        filkø.async { [self] in
            for fil in køFiler() { try? FileManager.default.removeItem(at: fil) }
        }
    }

    var antallIKø: Int {
        filkø.sync { køFiler().count }
    }

    // MARK: - Internt (alt på filkø-køen)

    private func køFiler() -> [URL] {
        let filer = (try? FileManager.default.contentsOfDirectory(
            at: køMappe, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return filer.filter { $0.pathExtension == "json" }.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return da < db
        }
    }

    private func beskjærKø() {
        let filer = køFiler()
        guard filer.count > konfig.maksIKø else { return }
        for fil in filer.prefix(filer.count - konfig.maksIKø) {
            try? FileManager.default.removeItem(at: fil)
        }
    }

    private func prøvOpplastingLåst() {
        guard let endepunkt = konfig.endepunkt, !lasterOpp else { return }
        let batch = Array(køFiler().prefix(konfig.maksPerOpplasting))
        guard !batch.isEmpty else { return }

        var partier: [Data] = []
        for fil in batch {
            if let data = try? Data(contentsOf: fil) { partier.append(data) }
        }
        // Bygg JSON-kroppen av de allerede-serialiserte opptakene.
        var kropp = Data("{\"partier\":[".utf8)
        kropp.append(partier.joined(separator: Data(",".utf8)))
        kropp.append(Data("]}".utf8))

        var forespørsel = URLRequest(url: endepunkt)
        forespørsel.httpMethod = "POST"
        forespørsel.setValue("application/json", forHTTPHeaderField: "Content-Type")
        forespørsel.setValue(konfig.appNøkkel, forHTTPHeaderField: "X-App-Nokkel")
        forespørsel.httpBody = kropp
        forespørsel.timeoutInterval = 30

        lasterOpp = true
        let oppgave = URLSession.shared.dataTask(with: forespørsel) { [weak self] _, svar, feil in
            guard let self else { return }
            self.filkø.async {
                self.lasterOpp = false
                guard feil == nil, let http = svar as? HTTPURLResponse else { return }
                switch http.statusCode {
                case 200..<300:
                    for fil in batch { try? FileManager.default.removeItem(at: fil) }
                    // Mer i køen? Fortsett til den er tom.
                    self.prøvOpplastingLåst()
                case 400..<500:
                    // Backenden avviste innholdet – ikke prøv de samme igjen.
                    for fil in batch { try? FileManager.default.removeItem(at: fil) }
                default:
                    break // 5xx: la filene ligge til neste forsøk.
                }
            }
        }
        oppgave.resume()
    }
}

private extension Array where Element == Data {
    func joined(separator: Data) -> Data {
        var resultat = Data()
        for (i, del) in enumerated() {
            if i > 0 { resultat.append(separator) }
            resultat.append(del)
        }
        return resultat
    }
}

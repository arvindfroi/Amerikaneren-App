import Foundation
#if canImport(Glibc)
import Glibc
#endif

// Lokal web-GUI for Amerikaneren:
//
//   swift run Amerikaneren web --port 8787
//
// starter en minimal HTTP-tjener (ren Foundation/POSIX-sockets, ingen nye
// avhengigheter) som binder til 127.0.0.1 og serverer en innebygd
// single-page-app pluss et JSON-API. Mennesket sitter i sete 0 og møter
// tre President-AI-er (MesterAI). AI-trekkene kjøres automatisk på en
// egen seriell kø etter hvert menneskelig trekk; klienten poller /state.
//
// API (alt sett fra sete 0 – de andre hendene, talongen og vraket
// serialiseres aldri, så devtools avslører ingenting):
//   GET  /state       full tilstand
//   GET  /forslag     trenerens anbefaling for menneskets gjeldende valg
//                     (egen MesterAI for sete 0 – ser kun lovlig info via
//                     Spillinnsikt; ved kortvalg følger en rangert
//                     kandidatliste med EV per kandidat)
//   GET  /logg        lister spilloggene i ~/spillogger (JSON)
//   GET  /logg/<fil>  innholdet i én logg – loggen for det PÅGÅENDE
//                     partiet er sperret (403) til partiet er ferdig,
//                     siden den inneholder alle hendene og talongen
//   POST /bud         {"action": "pass"|"amerikaner"|"solo"|tall}
//   POST /vrak        {"kort": ["♠14", ...]}   (kort-id = farge + rangtall)
//   POST /trumf       {"suit": "♠", "onsket": "♠12"?}
//   POST /spill       {"kort": "♠14"}
//   POST /nesteRunde  {}
//   POST /nyttParti   {}
//
// Spillogg (~/spillogger/parti-<tidsstempel>.jsonl, én JSON-linje per
// hendelse, i rekkefølge – «type»-feltet skiller):
//   meta         partistart: navn, målpoeng, tidsbudsjett, seed, versjon
//   utdeling     rundestart: alle fire hender + talong (kort-id-er) og
//                første budgiver – dette er hemmelighetene, derfor sperren
//                på den aktive loggen over
//   trekk        ett valg: runde, fase, sete, lovlige valg, valgt – og for
//                menneskets valg også trenerens forslag, kandidatrangering
//                (ved kortvalg) og om forslaget ble fulgt
//   rundeslutt   poengendringer, stikk per sete, sluttpoeng og
//                trenerstatistikken for runden
//   rundeopptak  hele runden som `Rundeopptak` (Innsamling/Opptak.swift) –
//                kan spilles av og verifiseres gjennom motoren med
//                `Rundeopptak.spillAv(regler:)`, samme infrastruktur som
//                treningsdataene bruker
//   partislutt   sluttpoeng og vinner
//   avbrutt      partiet ble forlatt (nytt parti startet før mål)

// MARK: - Kommandoen

enum WebSpill {

    #if os(Linux)
    private static let strømtype = Int32(SOCK_STREAM.rawValue)
    private static let sendFlagg = Int32(MSG_NOSIGNAL)
    #else
    private static let strømtype = SOCK_STREAM
    private static let sendFlagg: Int32 = 0
    #endif

    static func kjør(argv: [String]) {
        let port = flagg("port", argv).flatMap { UInt16($0) } ?? 8787
        var oppsett = WebSpilltjener.Oppsett()
        oppsett.seed = flagg("seed", argv).flatMap { UInt64($0) }
        if let mål = flagg("mål", argv).flatMap({ Int($0) }) { oppsett.målPoeng = mål }
        if let tid = flagg("tid", argv).flatMap({ Double($0) }) { oppsett.tidsbudsjett = tid }
        if let navn = flagg("navn", argv)?.trimmingCharacters(in: .whitespaces), !navn.isEmpty {
            oppsett.spillernavn = navn
        }

        let tjener = WebSpilltjener(oppsett: oppsett)
        tjener.start()

        signal(SIGPIPE, SIG_IGN)
        let lytter = socket(AF_INET, strømtype, 0)
        guard lytter >= 0 else {
            print("⚠️ Kunne ikke opprette socket.")
            exit(1)
        }
        var gjenbruk: Int32 = 1
        setsockopt(lytter, SOL_SOCKET, SO_REUSEADDR, &gjenbruk, socklen_t(MemoryLayout<Int32>.size))

        var adresse = sockaddr_in()
        adresse.sin_family = sa_family_t(AF_INET)
        adresse.sin_port = port.bigEndian
        adresse.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))   // kun localhost
        let bundet = withUnsafePointer(to: &adresse) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(lytter, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bundet == 0, listen(lytter, 16) == 0 else {
            print("⚠️ Kunne ikke lytte på 127.0.0.1:\(port) – er porten i bruk? (--port N velger en annen)")
            exit(1)
        }

        print("🌐 Amerikaneren web-GUI: http://127.0.0.1:\(port)")
        print("   \(oppsett.spillernavn) (sete 0) mot 3× President-AI · først til \(oppsett.målPoeng) poeng · Ctrl+C avslutter")

        while true {
            let klient = accept(lytter, nil, nil)
            guard klient >= 0 else { continue }
            DispatchQueue.global().async { håndterKlient(klient, tjener: tjener) }
        }
    }

    private static func flagg(_ navn: String, _ argv: [String]) -> String? {
        guard let i = argv.firstIndex(of: "--\(navn)"), i + 1 < argv.count else { return nil }
        return argv[i + 1]
    }

    // MARK: - HTTP-håndtering

    private static func håndterKlient(_ fd: Int32, tjener: WebSpilltjener) {
        defer { close(fd) }
        var frist = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &frist, socklen_t(MemoryLayout<timeval>.size))
        guard let forespørsel = lesForespørsel(fd) else { return }
        let sti = forespørsel.sti.split(separator: "?").first.map(String.init) ?? forespørsel.sti

        switch (forespørsel.metode, sti) {
        case ("GET", "/"), ("GET", "/index.html"):
            svar(fd, status: "200 OK", type: "text/html; charset=utf-8", kropp: Data(webSideHTML.utf8))
        case ("GET", "/state"), ("GET", "/forslag"), ("GET", "/logg"):
            let (status, data) = tjener.håndter(sti: sti, kroppData: nil)
            svar(fd, status: statusTekst(status), type: "application/json; charset=utf-8", kropp: data)
        case ("GET", _) where sti.hasPrefix("/logg/"):
            let navn = String(sti.dropFirst("/logg/".count)).removingPercentEncoding ?? ""
            let (status, data, type) = tjener.hentLogg(navn: navn)
            svar(fd, status: statusTekst(status), type: type, kropp: data)
        case ("POST", _):
            let (status, data) = tjener.håndter(sti: sti, kroppData: forespørsel.kropp)
            svar(fd, status: statusTekst(status), type: "application/json; charset=utf-8", kropp: data)
        default:
            svar(fd, status: "404 Not Found", type: "application/json; charset=utf-8",
                 kropp: Data("{\"feil\":\"Ukjent adresse\"}".utf8))
        }
    }

    private static func statusTekst(_ status: Int) -> String {
        switch status {
        case 200: return "200 OK"
        case 403: return "403 Forbidden"
        case 404: return "404 Not Found"
        default: return "400 Bad Request"
        }
    }

    /// Leser en HTTP-forespørsel: startlinje, hoder (kun Content-Length
    /// brukes) og kropp. Returnerer nil ved brutt/ugyldig forbindelse.
    private static func lesForespørsel(_ fd: Int32) -> (metode: String, sti: String, kropp: Data)? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        let skille = Data("\r\n\r\n".utf8)
        var hodeSlutt: Range<Data.Index>?
        while hodeSlutt == nil {
            let n = recv(fd, &buffer, buffer.count, 0)
            guard n > 0 else { return nil }
            data.append(contentsOf: buffer[0..<n])
            guard data.count < 1 << 20 else { return nil }
            hodeSlutt = data.range(of: skille)
        }
        guard let slutt = hodeSlutt,
              let hode = String(data: data[..<slutt.lowerBound], encoding: .utf8) else { return nil }

        let linjer = hode.components(separatedBy: "\r\n")
        let deler = linjer[0].split(separator: " ")
        guard deler.count >= 2 else { return nil }

        var lengde = 0
        for linje in linjer.dropFirst() {
            let biter = linje.split(separator: ":", maxSplits: 1)
            if biter.count == 2,
               biter[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                lengde = Int(biter[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        guard lengde < 1 << 20 else { return nil }

        var kropp = Data(data[slutt.upperBound...])
        while kropp.count < lengde {
            let n = recv(fd, &buffer, buffer.count, 0)
            guard n > 0 else { break }
            kropp.append(contentsOf: buffer[0..<n])
        }
        return (String(deler[0]).uppercased(), String(deler[1]), kropp)
    }

    private static func svar(_ fd: Int32, status: String, type: String, kropp: Data) {
        var ut = Data("HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(kropp.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8)
        ut.append(kropp)
        ut.withUnsafeBytes { (råe: UnsafeRawBufferPointer) in
            guard let start = råe.baseAddress else { return }
            var sendt = 0
            while sendt < ut.count {
                let n = send(fd, start + sendt, ut.count - sendt, sendFlagg)
                guard n > 0 else { return }
                sendt += n
            }
        }
    }
}

// MARK: - Spilltjeneren: motor + AI-er bak en seriell kø

/// Holder partiet (GameEngine + tre MesterAI-er) og kjører alt spillrelatert
/// på én seriell kø. Menneskets trekk håndteres synkront i forespørselen;
/// AI-trekkene legges på køen ett og ett, slik at GET /state kan flettes
/// inn mellom dem (klienten poller og venter aldri mer enn ett AI-trekk).
final class WebSpilltjener {

    struct Oppsett {
        var spillernavn = "Arvind"
        var målPoeng = 100
        var tidsbudsjett = 0.6      // per trekk – romslig, AI-ene skal tenke grundig
        var seed: UInt64?
    }

    private let oppsett: Oppsett
    private let kø = DispatchQueue(label: "amerikaneren.webspill")
    private var engine = GameEngine()
    private var mestere: [Int: MesterAI] = [:]
    private var trener: MesterAI?
    private var rundeNr = 1
    private var aiPlanlagt = false
    private var forslagPlanlagt = false
    private var gjeldendeForslag: Forslag?
    private var trenerStats = TrenerStatsJS()
    private var loggFil: FileHandle?
    private var loggNavn: String?
    private var partiLoggetFerdig = false
    let navn: [String]

    private static let loggKatalog = FileManager.default
        .homeDirectoryForCurrentUser.appendingPathComponent("spillogger")

    init(oppsett: Oppsett) {
        self.oppsett = oppsett
        self.navn = [oppsett.spillernavn, "Bjørn (AI)", "Kari (AI)", "Ola (AI)"]
    }

    /// Setter opp første parti og sparker i gang AI-ene (første budgiver er
    /// sete 1, altså en AI). Kalles én gang før tjeneren tar imot trafikk.
    func start() {
        kø.sync {
            byggParti()
            planleggAI()
            planleggForslag()
        }
    }

    // MARK: - API-inngangen (kalles fra forbindelsestrådene)

    func håndter(sti: String, kroppData: Data?) -> (Int, Data) {
        kø.sync { () -> (Int, Data) in
            switch sti {
            case "/state":
                return (200, tilstand())
            case "/forslag":
                return hentForslag()
            case "/logg":
                return listLogger()
            case "/nyttParti":
                byggParti()
                planleggAI()
                planleggForslag()
                return (200, tilstand())
            case "/nesteRunde":
                guard engine.phase == .rundeFerdig else { return feil("Runden er ikke ferdig.") }
                rundeNr += 1
                engine.startRunde(seed: rundeSeed())
                loggNyRunde()
                planleggAI()
                planleggForslag()
                return (200, tilstand())
            case "/bud":
                return håndterBud(kropp(kroppData))
            case "/vrak":
                return håndterVrak(kropp(kroppData))
            case "/trumf":
                return håndterTrumf(kropp(kroppData))
            case "/spill":
                return håndterSpill(kropp(kroppData))
            default:
                return (404, Data("{\"feil\":\"Ukjent adresse\"}".utf8))
            }
        }
    }

    /// Innholdet i én loggfil – med sperre for det pågående partiet, siden
    /// loggen inneholder alle hendene og talongen.
    func hentLogg(navn: String) -> (Int, Data, String) {
        kø.sync { () -> (Int, Data, String) in
            let json = "application/json; charset=utf-8"
            let gyldig = !navn.isEmpty && navn.hasSuffix(".jsonl")
                && navn.allSatisfy { $0.isLetter || $0.isNumber || "._-".contains($0) }
                && !navn.contains("..")
            guard gyldig else {
                return (400, Data("{\"feil\":\"Ugyldig filnavn\"}".utf8), json)
            }
            if navn == loggNavn, !partiLoggetFerdig {
                let feil = "{\"feil\":\"Loggen for det pågående partiet er sperret til partiet er ferdig – den inneholder alle hendene og talongen.\"}"
                return (403, Data(feil.utf8), json)
            }
            let url = Self.loggKatalog.appendingPathComponent(navn)
            guard let data = try? Data(contentsOf: url) else {
                return (404, Data("{\"feil\":\"Fant ikke loggen\"}".utf8), json)
            }
            return (200, data, "text/plain; charset=utf-8")
        }
    }

    // MARK: - Menneskets trekk (alle kjører på køen)

    private func håndterBud(_ kropp: [String: Any]) -> (Int, Data) {
        guard engine.phase == .budrunde, engine.aktivBudgiver == 0 else {
            return feil("Det er ikke din tur til å by.")
        }
        guard let handling = budHandling(fra: kropp["action"]) else { return feil("Ugyldig bud.") }
        let lovlige = engine.lovligeBud(for: 0)
        guard lovlige.contains(handling) else { return feil("Budet er ikke lovlig nå.") }
        let forslag = forslagFor(nøkkel: beslutningsnøkkel)
        engine.giBud(seat: 0, action: handling)
        var fulgt = false
        if case .bud(let anbefalt)? = forslag?.valg { fulgt = anbefalt == handling }
        loggMenneskeTrekk(fase: "budrunde", lovlige: lovlige.map(budId),
                          valgt: budId(handling), valgtTekst: handling.beskrivelse,
                          forslag: forslag, fulgt: fulgt)
        etterTrekk()
        return (200, tilstand())
    }

    private func håndterVrak(_ kropp: [String: Any]) -> (Int, Data) {
        guard engine.phase == .byttekort, engine.budgiverSeat == 0 else {
            return feil("Det er ikke du som skal vrake nå.")
        }
        let antall = engine.rules.antallByttekort
        guard let ider = kropp["kort"] as? [String] else { return feil("Mangler kortlisten «kort».") }
        let kort = ider.compactMap(Self.kort(fraId:))
        let hånd = engine.hands[0]
        let forslag = forslagFor(nøkkel: beslutningsnøkkel)
        guard kort.count == antall, engine.kastByttekort(kort, seat: 0) else {
            return feil("Vraket må være nøyaktig \(antall) ulike kort fra hånden din.")
        }
        var fulgt = false
        if case .vrak(let anbefalt)? = forslag?.valg { fulgt = anbefalt == Set(kort) }
        loggMenneskeTrekk(fase: "byttekort", lovlige: hånd.map(\.id),
                          valgt: kort.map(\.id).joined(separator: "+"),
                          valgtTekst: kort.map(\.kortSymbol).joined(separator: " "),
                          forslag: forslag, fulgt: fulgt)
        etterTrekk()
        return (200, tilstand())
    }

    private func håndterTrumf(_ kropp: [String: Any]) -> (Int, Data) {
        guard engine.phase == .velgTrumf, engine.budgiverSeat == 0 else {
            return feil("Det er ikke du som skal velge trumf nå.")
        }
        guard let symbol = kropp["suit"] as? String, let farge = Suit(rawValue: symbol) else {
            return feil("Ugyldig trumffarge – bruk ♠, ♥, ♦ eller ♣.")
        }
        let ønsketId = (kropp["ønsket"] as? String) ?? (kropp["onsket"] as? String)
        let ønsket = ønsketId.flatMap(Self.kort(fraId:))
        if ønsketId != nil, ønsket == nil { return feil("Ugyldig ønskekort.") }
        let forslag = forslagFor(nøkkel: beslutningsnøkkel)
        guard engine.velgTrumf(suit: farge, ønsket: ønsket) else {
            return feil(ønsket == nil
                ? "Etterlysning er obligatorisk (bare solo-amerikaner kan droppe den)."
                : "Kortet kan ikke etterlyses – velg et trumfkort du verken har eller har vraket.")
        }
        var fulgt = false
        if case .trumf(let aFarge, let aØnsket)? = forslag?.valg {
            fulgt = aFarge == farge && aØnsket == ønsket
        }
        loggMenneskeTrekk(fase: "velgTrumf", lovlige: Suit.allCases.map(\.rawValue),
                          valgt: farge.rawValue + (ønsket.map { "+\($0.id)" } ?? ""),
                          valgtTekst: trumfTekst(farge, ønsket),
                          forslag: forslag, fulgt: fulgt)
        etterTrekk()
        return (200, tilstand())
    }

    private func håndterSpill(_ kropp: [String: Any]) -> (Int, Data) {
        guard engine.phase == .spill, engine.aktivSpiller == 0 else {
            return feil("Det er ikke din tur.")
        }
        guard let id = kropp["kort"] as? String, let kort = Self.kort(fraId: id) else {
            return feil("Mangler eller ugyldig «kort».")
        }
        let lovlige = engine.lovligeKort(for: 0)
        let forslag = forslagFor(nøkkel: beslutningsnøkkel)
        guard engine.spill(kort: kort, seat: 0) else {
            return feil("Kortet er ikke lovlig å spille nå (følg farge – og husk pliktene i første stikk).")
        }
        var fulgt = false
        if case .kort(let anbefalt, let likeverdige)? = forslag?.valg {
            // Likeverdige kort (samme sekvens) teller som å følge forslaget.
            fulgt = anbefalt == kort || likeverdige.contains(kort)
        }
        loggMenneskeTrekk(fase: "spill", lovlige: lovlige.map(\.id),
                          valgt: kort.id, valgtTekst: kort.kortSymbol,
                          forslag: forslag, fulgt: fulgt)
        etterTrekk()
        return (200, tilstand())
    }

    /// Felles hale etter hvert utførte trekk (menneske eller AI): logg
    /// rundeslutt om runden nettopp ble ferdig, og sett i gang neste
    /// AI-trekk / trenerforslag.
    private func etterTrekk() {
        sjekkRundeSlutt()
        planleggAI()
        planleggForslag()
    }

    // MARK: - Parti- og AI-styring

    private func byggParti() {
        // Lukk (og eventuelt «avbrutt»-merk) forrige partis logg mens den
        // gamle motoren ennå har poengstillingen, og åpne en ny.
        åpneNyLogg()

        var regler = GameRules()
        regler.målPoeng = oppsett.målPoeng
        engine = GameEngine(rules: regler)
        rundeNr = 1

        var konfig = Kampsimulator.mesterKonfig(tidsbudsjett: oppsett.tidsbudsjett)
        if oppsett.tidsbudsjett > 0.1 {
            // Grundig tenking i web-spillet: midtspillet stopper ellers på
            // verdenstaket (36) lenge før tidsbudsjettet er brukt.
            konfig.maksVerdener = 120
        }
        MesterAI.overstyrKonfig = konfig
        mestere = [:]
        for sete in 1...3 {
            mestere[sete] = MesterAI(
                sete: sete, konfig: konfig,
                seed: oppsett.seed.map { $0 &+ UInt64(sete) &* 7919 }
            )
        }
        // Treneren: en egen MesterAI for menneskets sete. Den ser aldri
        // skjult informasjon (alt går via Spillinnsikt) og bruker samme
        // romslige konfigurasjon som motstanderne.
        trener = MesterAI(sete: 0, konfig: konfig,
                          seed: oppsett.seed.map { $0 &+ 104_729 })
        gjeldendeForslag = nil
        engine.startRunde(seed: rundeSeed())
        loggNyRunde()
    }

    private func rundeSeed() -> UInt64? {
        oppsett.seed.map { $0 &+ UInt64(rundeNr) &* 0x9E37 }
    }

    /// Setet som er i tur i den aktive fasen – nil når ingen skal gjøre noe.
    private var seteITur: Int? {
        switch engine.phase {
        case .budrunde: return engine.aktivBudgiver
        case .byttekort, .velgTrumf: return engine.budgiverSeat
        case .spill: return engine.aktivSpiller
        default: return nil
        }
    }

    /// Legger neste AI-trekk på køen hvis en AI er i tur. Ett trekk per
    /// kø-oppgave, så /state slipper til mellom trekkene.
    private func planleggAI() {
        guard !aiPlanlagt, let sete = seteITur, sete != 0 else { return }
        aiPlanlagt = true
        kø.async { self.kjørEttAITrekk() }
    }

    private func kjørEttAITrekk() {
        aiPlanlagt = false
        guard let sete = seteITur, sete != 0 else { return }
        switch engine.phase {
        case .budrunde:
            let lovlige = engine.lovligeBud(for: sete)
            let valg = aiBud(sete: sete, mester: mestere[sete])
            engine.giBud(seat: sete, action: valg)
            loggTrekk(fase: "budrunde", sete: sete,
                      lovlige: lovlige.map(budId), valgt: budId(valg))
        case .byttekort:
            let hånd = engine.hands[sete]
            let valg = aiVrak(sete: sete, mester: mestere[sete])
            engine.kastByttekort(valg, seat: sete)
            loggTrekk(fase: "byttekort", sete: sete, lovlige: hånd.map(\.id),
                      valgt: valg.map(\.id).joined(separator: "+"))
        case .velgTrumf:
            let (farge, ønsket) = aiTrumf(sete: sete, mester: mestere[sete])
            engine.velgTrumf(suit: farge, ønsket: ønsket)
            loggTrekk(fase: "velgTrumf", sete: sete,
                      lovlige: Suit.allCases.map(\.rawValue),
                      valgt: farge.rawValue + (ønsket.map { "+\($0.id)" } ?? ""))
        case .spill:
            let lovlige = engine.lovligeKort(for: sete)
            let valg = aiKort(sete: sete, mester: mestere[sete])
            engine.spill(kort: valg, seat: sete)
            loggTrekk(fase: "spill", sete: sete, lovlige: lovlige.map(\.id), valgt: valg.id)
        default:
            break
        }
        etterTrekk()
    }

    // AI-valg med trygge fallbacks – samme mønster som Kampsimulator/SpillKommando.
    // `mester` sendes eksplisitt slik at treneren (sete 0) bruker samme vei.

    private func aiBud(sete: Int, mester: MesterAI?) -> BidAction {
        let lovlige = engine.lovligeBud(for: sete)
        if let mester {
            let bud = mester.velgBud(engine: engine)
            if lovlige.contains(bud) { return bud }
        }
        return .pass
    }

    private func aiVrak(sete: Int, mester: MesterAI?) -> [Card] {
        let antall = engine.rules.antallByttekort
        let hånd = engine.hands[sete]
        if let mester {
            let vrak = mester.velgByttekort(engine: engine)
            if vrak.count == antall, vrak.allSatisfy({ hånd.contains($0) }) { return vrak }
        }
        return Array(hånd.suffix(antall))
    }

    private func aiTrumf(sete: Int, mester: MesterAI?) -> (Suit, Card?) {
        if let mester, let valg = mester.velgTrumfOgMakker(engine: engine),
           valg.1 == nil || engine.kortSomKanØnskes(trumf: valg.0).contains(valg.1!) {
            return valg
        }
        // Fallback: lengste farge; finnes ingen ønskbare kort der, ta første
        // farge som har noen (ellers solo uten etterlysning).
        let hånd = engine.hands[sete]
        func antallI(_ farge: Suit) -> Int { hånd.filter { $0.suit == farge }.count }
        let lengste = Suit.allCases.max { antallI($0) < antallI($1) } ?? .spar
        if let kandidat = engine.kortSomKanØnskes(trumf: lengste).first { return (lengste, kandidat) }
        for farge in Suit.allCases {
            if let kandidat = engine.kortSomKanØnskes(trumf: farge).first { return (farge, kandidat) }
        }
        return (lengste, nil)
    }

    private func aiKort(sete: Int, mester: MesterAI?) -> Card {
        let lovlige = engine.lovligeKort(for: sete)
        if let mester, let kort = mester.velgKort(engine: engine), lovlige.contains(kort) {
            return kort
        }
        return lovlige[0]
    }

    // MARK: - Treneren (forslag for menneskets valg)

    /// Trenerens anbefaling for ett beslutningspunkt, med både maskinlesbar
    /// form (til sammenlikning/logg) og ferdig JSON til klienten.
    private struct Forslag {
        var nøkkel: String
        var valg: TrenerValg
        var tekst: String
        var js: ForslagJS
    }

    private enum TrenerValg {
        case bud(BidAction)
        case vrak(Set<Card>)
        case trumf(Suit, Card?)
        case kort(Card, likeverdige: Set<Card>)
    }

    /// Entydig nøkkel for menneskets gjeldende beslutningspunkt – nil når
    /// det ikke er menneskets tur. Hvert valg endrer budlisten, fasen
    /// eller spilte kort, så nøkkelen er unik gjennom partiet.
    private var beslutningsnøkkel: String? {
        guard seteITur == 0 else { return nil }
        return "\(rundeNr):\(engine.phase.rawValue):\(engine.bids.count):\(engine.spilteKort.count)"
    }

    /// Legger beregningen av neste trenerforslag på køen når mennesket er i
    /// tur. Kjøres asynkront (som AI-trekkene), så /state blokkeres aldri av
    /// et halvferdig forslag – og fordi køen er seriell er forslaget alltid
    /// beregnet før menneskets trekk (som står bak i køen) håndteres.
    private func planleggForslag() {
        guard let nøkkel = beslutningsnøkkel,
              gjeldendeForslag?.nøkkel != nøkkel, !forslagPlanlagt else { return }
        forslagPlanlagt = true
        kø.async { self.beregnForslag() }
    }

    private func beregnForslag() {
        forslagPlanlagt = false
        guard let nøkkel = beslutningsnøkkel, gjeldendeForslag?.nøkkel != nøkkel else { return }
        gjeldendeForslag = lagForslag(nøkkel: nøkkel)
    }

    /// Forslaget for nøkkelen – fra mellomlageret, ellers beregnet nå.
    private func forslagFor(nøkkel: String?) -> Forslag? {
        guard let nøkkel else { return nil }
        if gjeldendeForslag?.nøkkel != nøkkel { gjeldendeForslag = lagForslag(nøkkel: nøkkel) }
        return gjeldendeForslag
    }

    /// GET /forslag: anbefalingen for menneskets gjeldende valg. Svaret
    /// bygger utelukkende på sete 0s lovlige informasjon (egen hånd og
    /// åpne opplysninger) – aldri de andres kort.
    private func hentForslag() -> (Int, Data) {
        guard let nøkkel = beslutningsnøkkel, let forslag = forslagFor(nøkkel: nøkkel) else {
            return (200, kodJSON(ForslagJS(aktuelt: false)))
        }
        return (200, kodJSON(forslag.js))
    }

    private func lagForslag(nøkkel: String) -> Forslag? {
        var js = ForslagJS(aktuelt: true)
        js.nokkel = nøkkel
        js.fase = engine.phase.rawValue
        let start = Date()
        let valg: TrenerValg
        let tekst: String

        switch engine.phase {
        case .budrunde:
            let handling = aiBud(sete: 0, mester: trener)
            js.bud = BudJS(id: budId(handling), tekst: handling.beskrivelse)
            valg = .bud(handling)
            tekst = handling.beskrivelse
        case .byttekort:
            let vrak = aiVrak(sete: 0, mester: trener)
            js.vrak = vrak.map(kortJS)
            valg = .vrak(Set(vrak))
            tekst = vrak.map(\.kortSymbol).joined(separator: " ")
        case .velgTrumf:
            let (farge, ønsket) = aiTrumf(sete: 0, mester: trener)
            js.trumf = farge.rawValue
            js.trumfNavn = farge.navn
            js.onsket = ønsket.map(kortJS)
            valg = .trumf(farge, ønsket)
            tekst = trumfTekst(farge, ønsket)
        case .spill:
            let lovlige = engine.lovligeKort(for: 0)
            guard !lovlige.isEmpty else { return nil }
            if let r = trener?.velgKortMedRangering(engine: engine), lovlige.contains(r.valg) {
                js.kort = kortJS(r.valg)
                js.verdener = r.verdener
                js.rangering = r.kandidater.map { kandidat in
                    ForslagKortJS(kort: kortJS(kandidat.kort),
                                  verdi: (kandidat.verdi * 100).rounded() / 100,
                                  likeverdige: kandidat.likeverdige.map(\.id))
                }
                let like = r.kandidater.first { $0.kort == r.valg }?.likeverdige ?? [r.valg]
                valg = .kort(r.valg, likeverdige: Set(like))
                tekst = r.valg.kortSymbol
            } else {
                js.kort = kortJS(lovlige[0])
                valg = .kort(lovlige[0], likeverdige: [lovlige[0]])
                tekst = lovlige[0].kortSymbol
            }
        default:
            return nil
        }

        js.beregnetMs = Int(Date().timeIntervalSince(start) * 1000)
        return Forslag(nøkkel: nøkkel, valg: valg, tekst: tekst, js: js)
    }

    private func trumfTekst(_ farge: Suit, _ ønsket: Card?) -> String {
        "\(farge.rawValue) \(farge.navn)"
            + (ønsket.map { ", etterlys \($0.kortSymbol)" } ?? ", uten etterlysning")
    }

    private func kodJSON<T: Encodable>(_ verdi: T) -> Data {
        let koder = JSONEncoder()
        koder.outputFormatting = [.sortedKeys]
        return (try? koder.encode(verdi)) ?? Data("{}".utf8)
    }

    // MARK: - Spilloggen (~/spillogger, én JSONL-fil per parti)

    /// Åpner en ny loggfil for et nytt parti; et uferdig parti merkes
    /// «avbrutt» først. Feiler katalogen/filen, spilles det videre uten logg.
    private func åpneNyLogg() {
        lukkLogg()
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.loggKatalog, withIntermediateDirectories: true)
        let format = DateFormatter()
        format.dateFormat = "yyyyMMdd-HHmmss"
        let stempel = format.string(from: Date())
        var navn = "parti-\(stempel).jsonl"
        var løpenr = 2
        while fm.fileExists(atPath: Self.loggKatalog.appendingPathComponent(navn).path) {
            navn = "parti-\(stempel)-\(løpenr).jsonl"
            løpenr += 1
        }
        let url = Self.loggKatalog.appendingPathComponent(navn)
        guard fm.createFile(atPath: url.path, contents: nil),
              let fil = try? FileHandle(forWritingTo: url) else {
            loggFil = nil
            loggNavn = nil
            return
        }
        loggFil = fil
        loggNavn = navn
        partiLoggetFerdig = false
        skrivLogg(LoggMeta(navn: navn, dato: ISO8601DateFormatter().string(from: Date()),
                           spillere: self.navn, maalPoeng: oppsett.målPoeng,
                           tidsbudsjett: oppsett.tidsbudsjett, seed: oppsett.seed))
    }

    private func lukkLogg() {
        if let fil = loggFil {
            if !partiLoggetFerdig { skrivLogg(LoggAvbrutt(poeng: engine.scores)) }
            try? fil.close()
        }
        loggFil = nil
        loggNavn = nil
        partiLoggetFerdig = false
    }

    private func skrivLogg<T: Encodable>(_ linje: T) {
        guard let fil = loggFil, var data = try? JSONEncoder().encode(linje) else { return }
        data.append(0x0A)
        try? fil.write(contentsOf: data)
    }

    /// Rundestart: nullstill trenerstatistikken og logg hele utdelingen
    /// (alle hender + talong). Dette er grunnen til at den aktive loggen
    /// er sperret for klienten til partiet er ferdig.
    private func loggNyRunde() {
        trenerStats = TrenerStatsJS()
        gjeldendeForslag = nil
        skrivLogg(LoggUtdeling(runde: rundeNr,
                               forsteBudgiver: engine.førsteBudgiverIRunden,
                               hender: engine.utdelteHender.map { $0.map(\.id) },
                               talon: engine.utdeltTalon.map(\.id)))
    }

    private func loggTrekk(fase: String, sete: Int, lovlige: [String], valgt: String) {
        skrivLogg(LoggTrekk(runde: rundeNr, fase: fase, sete: sete,
                            lovlige: lovlige, valgt: valgt,
                            forslag: nil, rangering: nil, fulgt: nil))
    }

    private func loggMenneskeTrekk(fase: String, lovlige: [String], valgt: String,
                                   valgtTekst: String, forslag: Forslag?, fulgt: Bool) {
        skrivLogg(LoggTrekk(runde: rundeNr, fase: fase, sete: 0,
                            lovlige: lovlige, valgt: valgt,
                            forslag: forslag?.tekst, rangering: forslag?.js.rangering,
                            fulgt: fulgt))
        trenerStats.totalt += 1
        if fulgt {
            trenerStats.fulgt += 1
        } else if let forslag {
            trenerStats.avvik.append(TrenerAvvikJS(fase: fase, valgt: valgtTekst,
                                                   forslag: forslag.tekst))
        }
    }

    /// Ble runden (eller partiet) nettopp ferdig, logges resultatet og hele
    /// runden som `Rundeopptak` – avspillbar og verifiserbar gjennom motoren.
    private func sjekkRundeSlutt() {
        guard engine.phase == .rundeFerdig || engine.phase == .spillFerdig,
              let resultat = engine.sisteRunde else { return }
        skrivLogg(LoggRundeSlutt(runde: rundeNr, klarte: resultat.klarte,
                                 poengEndring: resultat.poengEndring,
                                 stikkPerSpiller: resultat.stikkPerSpiller,
                                 poeng: engine.scores, trener: trenerStats))
        if let opptak = Rundeopptak(fra: engine) {
            skrivLogg(LoggOpptak(runde: rundeNr, opptak: opptak))
        }
        if engine.phase == .spillFerdig {
            skrivLogg(LoggSlutt(poeng: engine.scores, vinner: engine.vinnerSeat))
            partiLoggetFerdig = true
        }
    }

    /// GET /logg: loggfilene i ~/spillogger, nyeste først. Den aktive
    /// (sperrede) er merket.
    private func listLogger() -> (Int, Data) {
        let fm = FileManager.default
        let urler = (try? fm.contentsOfDirectory(at: Self.loggKatalog,
                                                 includingPropertiesForKeys: [.fileSizeKey]))
            ?? []
        let filer = urler
            .filter { $0.pathExtension == "jsonl" }
            .map { url -> LoggFilJS in
                let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return LoggFilJS(navn: url.lastPathComponent, bytes: bytes,
                                 aktiv: url.lastPathComponent == loggNavn && !partiLoggetFerdig)
            }
            .sorted { $0.navn > $1.navn }
        return (200, kodJSON(LoggListeJS(katalog: Self.loggKatalog.path, filer: filer)))
    }

    // MARK: - Inn- og utpakking

    private func kropp(_ data: Data?) -> [String: Any] {
        guard let data, !data.isEmpty,
              let objekt = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return objekt
    }

    private func budHandling(fra verdi: Any?) -> BidAction? {
        if let tekst = (verdi as? String)?.lowercased() {
            switch tekst {
            case "pass": return .pass
            case "amerikaner": return .amerikaner
            case "solo", "soloamerikaner", "solo-amerikaner": return .soloAmerikaner
            default: return Int(tekst).map { .bud($0) }
            }
        }
        if let tall = verdi as? Int { return .bud(tall) }
        return nil
    }

    /// Kort-id-en er `Card.id`: fargesymbol + rangtall, f.eks. "♠14" for spar ess.
    static func kort(fraId id: String) -> Card? {
        guard let symbol = id.first, let farge = Suit(rawValue: String(symbol)),
              let verdi = Int(id.dropFirst()), let rang = Rank(rawValue: verdi) else { return nil }
        return Card(suit: farge, rank: rang)
    }

    private func feil(_ tekst: String) -> (Int, Data) {
        ((try? JSONEncoder().encode(["feil": tekst])).map { (400, $0) }) ?? (400, Data("{}".utf8))
    }

    // MARK: - Tilstanden sett fra sete 0

    private func tilstand() -> Data {
        var t = TilstandJS()
        t.fase = engine.phase.rawValue
        t.runde = engine.rundeResultater.count
            + (engine.phase == .rundeFerdig || engine.phase == .spillFerdig ? 0 : 1)
        t.maalPoeng = engine.rules.målPoeng
        t.navn = navn
        t.poeng = engine.scores
        t.stikkTatt = engine.stikkTatt
        t.antallKort = engine.hands.map(\.count)
        t.aktivSete = seteITur
        t.dinTur = seteITur == 0
        t.aiTenker = seteITur != nil && seteITur != 0
        t.haand = engine.hands[0].map(kortJS)
        t.lovligeBud = engine.lovligeBud(for: 0).map { BudJS(id: budId($0), tekst: $0.beskrivelse) }
        t.budHistorikk = engine.bids.map { BudLinjeJS(sete: $0.seat, tekst: $0.action.beskrivelse) }
        t.hoyesteBud = engine.høyesteBud.map { BudLinjeJS(sete: $0.seat, tekst: $0.action.beskrivelse) }
        t.budgiver = engine.phase == .budrunde ? nil : engine.budgiverSeat
        t.trumf = engine.trumf?.rawValue
        t.trumfNavn = engine.trumf?.navn
        t.onsket = engine.ønsketKort.map(kortJS)
        t.onsketLagt = engine.ønsketLagt
        t.erAmerikaner = engine.erAmerikaner
        t.erSolo = engine.erSolo
        t.makkerAvslort = engine.makkerAvslørt
        t.makker = engine.makkerAvslørt ? engine.makkerSeat : nil   // hemmelig ellers
        t.bordet = engine.currentTrick.map { SpiltJS(sete: $0.seat, kort: kortJS($0.card)) }
        t.sisteStikk = engine.sisteStikk.map { SpiltJS(sete: $0.seat, kort: kortJS($0.card)) }
        t.sisteStikkVinner = engine.sisteStikkVinner
        t.stikkNummer = min(engine.trickNummer + 1, engine.rules.kortPerSpiller)
        t.antallStikkIRunden = engine.rules.kortPerSpiller

        if engine.phase == .byttekort, engine.budgiverSeat == 0 {
            t.vrakAntall = engine.rules.antallByttekort
        }
        if engine.phase == .velgTrumf, engine.budgiverSeat == 0 {
            t.trumfValg = Suit.allCases.map { farge in
                TrumfValgJS(farge: farge.rawValue, navn: farge.navn,
                            kandidater: engine.kortSomKanØnskes(trumf: farge).map(kortJS))
            }
            t.kanUtenOnske = engine.erSolo
        }

        let lovlige = engine.lovligeKort(for: 0)
        t.lovligeKort = lovlige.map(\.id)
        t.makkerplikt = lovlige.count == 1 && lovlige.first == engine.ønsketKort && engine.budgiverSeat != 0
        t.utspillsplikt = engine.phase == .spill && seteITur == 0 && engine.trickNummer == 0
            && engine.budgiverSeat == 0 && engine.currentTrick.isEmpty && engine.trumf != nil
            && !lovlige.isEmpty && lovlige.allSatisfy { $0.suit == engine.trumf }

        t.sisteRunde = engine.sisteRunde.map { runde in
            RundeJS(budgiver: runde.budgiver,
                    makker: runde.makker,
                    budTekst: runde.bud.beskrivelse,
                    trumf: runde.trumf?.rawValue,
                    stikkLaget: [runde.budgiver, runde.makker].compactMap { $0 }
                        .reduce(0) { $0 + runde.stikkPerSpiller[$1] },
                    klarte: runde.klarte,
                    poengEndring: runde.poengEndring,
                    stikkPerSpiller: runde.stikkPerSpiller)
        }
        t.vinner = engine.vinnerSeat
        t.partiFerdig = engine.phase == .spillFerdig
        t.trener = trenerStats
        t.forslagNokkel = beslutningsnøkkel
        t.loggNavn = loggNavn

        // Sortert nøkkelrekkefølge gjør svaret deterministisk, slik at
        // klienten kan sammenlikne rå JSON og bare re-rendre ved endring.
        let koder = JSONEncoder()
        koder.outputFormatting = [.sortedKeys]
        return (try? koder.encode(t)) ?? Data("{}".utf8)
    }

    private func kortJS(_ kort: Card) -> KortJS {
        KortJS(id: kort.id, tekst: kort.kortSymbol, farge: kort.suit.rawValue, roed: kort.suit.erRød)
    }

    private func budId(_ bud: BidAction) -> String {
        switch bud {
        case .pass: return "pass"
        case .bud(let n): return String(n)
        case .amerikaner: return "amerikaner"
        case .soloAmerikaner: return "solo"
        }
    }
}

// MARK: - Etterprøving av spillogger

/// `Amerikaneren verifiser <spillogg.jsonl> …` – spiller av hver
/// `rundeopptak`-linje i web-loggen gjennom den ekte motoren
/// (`Rundeopptak.spillAv`), som håndhever reglene trekk for trekk og
/// sammenlikner sluttresultatet. Én kommando – samme garanti som
/// treningsdata-importen gir.
enum VerifiserLogg {

    private struct Linje: Decodable {
        let type: String
        let runde: Int?
        let opptak: Rundeopptak?
        let maalPoeng: Int?
    }

    static func kjør(argv: [String]) {
        let stier = argv.dropFirst()
        guard !stier.isEmpty else {
            print("Bruk: Amerikaneren verifiser <spillogg.jsonl> [flere …]")
            exit(1)
        }
        var feil = 0
        let dekoder = JSONDecoder()
        for sti in stier {
            guard let data = FileManager.default.contents(atPath: sti),
                  let tekst = String(data: data, encoding: .utf8) else {
                print("⚠️ Kunne ikke lese \(sti)")
                feil += 1
                continue
            }
            var regler = GameRules()   // målPoeng fra meta-linjen styrer poengsatsene
            var verifisert = 0
            var filfeil = 0
            for (nr, rå) in tekst.split(separator: "\n").enumerated() {
                guard let linje = try? dekoder.decode(Linje.self, from: Data(rå.utf8)) else {
                    print("✗ \(sti):\(nr + 1): uleselig logglinje")
                    filfeil += 1
                    continue
                }
                if linje.type == "meta", let mål = linje.maalPoeng { regler.målPoeng = mål }
                guard linje.type == "rundeopptak", let opptak = linje.opptak else { continue }
                do {
                    try opptak.spillAv(regler: regler)
                    verifisert += 1
                } catch {
                    print("✗ \(sti): runde \(linje.runde.map(String.init) ?? "?"): \(error)")
                    filfeil += 1
                }
            }
            feil += filfeil
            print("\(filfeil == 0 ? "✓" : "✗") \(sti): \(verifisert) runder avspilt og verifisert gjennom motoren"
                  + (filfeil > 0 ? " – \(filfeil) FEIL" : ""))
        }
        exit(feil == 0 ? 0 : 1)
    }
}

// MARK: - JSON-modeller (ASCII-nøkler for enkel JS-tilgang)

private struct KortJS: Codable {
    var id: String      // "♠14"
    var tekst: String   // "A♠"
    var farge: String   // "♠"
    var roed: Bool
}

private struct BudJS: Codable {
    var id: String      // "pass" | "5"… | "amerikaner" | "solo"
    var tekst: String
}

private struct BudLinjeJS: Codable {
    var sete: Int
    var tekst: String
}

private struct SpiltJS: Codable {
    var sete: Int
    var kort: KortJS
}

private struct TrumfValgJS: Codable {
    var farge: String
    var navn: String
    var kandidater: [KortJS]
}

private struct RundeJS: Codable {
    var budgiver: Int
    var makker: Int?
    var budTekst: String
    var trumf: String?
    var stikkLaget: Int
    var klarte: Bool
    var poengEndring: [Int]
    var stikkPerSpiller: [Int]
}

// Treneren og loggen

private struct ForslagKortJS: Codable {
    var kort: KortJS
    var verdi: Double        // vektet snitt-EV over de samplede verdenene
    var likeverdige: [String]  // kort-id-er som er utbyttbare med kandidaten
}

private struct ForslagJS: Codable {
    var aktuelt: Bool          // false: ikke menneskets tur
    var nokkel: String?        // beslutningsnøkkelen (matcher /state)
    var fase: String?
    var bud: BudJS?            // budrunde: anbefalt melding
    var vrak: [KortJS]?        // byttekort: anbefalte vrakkort
    var trumf: String?         // velgTrumf: anbefalt farge …
    var trumfNavn: String?
    var onsket: KortJS?        // … og etterlysning (nil = uten)
    var kort: KortJS?          // spill: anbefalt kort
    var rangering: [ForslagKortJS]?  // spill: kandidatene, best først
    var verdener: Int?         // antall samplede verdener bak rangeringen
    var beregnetMs: Int?
}

private struct TrenerAvvikJS: Codable {
    var fase: String
    var valgt: String
    var forslag: String
}

private struct TrenerStatsJS: Codable {
    var totalt = 0
    var fulgt = 0
    var avvik: [TrenerAvvikJS] = []
}

private struct LoggFilJS: Codable {
    var navn: String
    var bytes: Int
    var aktiv: Bool   // det pågående partiets logg – sperret til partislutt
}

private struct LoggListeJS: Codable {
    var katalog: String
    var filer: [LoggFilJS]
}

// Logglinjene (én JSON-linje per hendelse; «type» skiller – se filhodet)

private struct LoggMeta: Codable {
    var type = "meta"
    var format = 1
    var navn: String
    var dato: String
    var spillere: [String]
    var maalPoeng: Int
    var tidsbudsjett: Double
    var seed: UInt64?
}

private struct LoggUtdeling: Codable {
    var type = "utdeling"
    var runde: Int
    var forsteBudgiver: Int
    var hender: [[String]]   // kort-id-er per sete – skjult info til partislutt
    var talon: [String]
}

private struct LoggTrekk: Codable {
    var type = "trekk"
    var runde: Int
    var fase: String
    var sete: Int
    var lovlige: [String]
    var valgt: String
    var forslag: String?             // kun menneskets trekk
    var rangering: [ForslagKortJS]?  // kun menneskets kortvalg
    var fulgt: Bool?
}

private struct LoggRundeSlutt: Codable {
    var type = "rundeslutt"
    var runde: Int
    var klarte: Bool
    var poengEndring: [Int]
    var stikkPerSpiller: [Int]
    var poeng: [Int]
    var trener: TrenerStatsJS
}

private struct LoggOpptak: Codable {
    var type = "rundeopptak"
    var runde: Int
    var opptak: Rundeopptak   // avspillbar via Rundeopptak.spillAv(regler:)
}

private struct LoggSlutt: Codable {
    var type = "partislutt"
    var poeng: [Int]
    var vinner: Int?
}

private struct LoggAvbrutt: Codable {
    var type = "avbrutt"
    var poeng: [Int]
}

private struct TilstandJS: Codable {
    var fase = ""
    var runde = 0
    var maalPoeng = 0
    var navn: [String] = []
    var poeng: [Int] = []
    var stikkTatt: [Int] = []
    var antallKort: [Int] = []
    var aktivSete: Int?
    var dinTur = false
    var aiTenker = false
    var haand: [KortJS] = []
    var lovligeKort: [String] = []
    var lovligeBud: [BudJS] = []
    var budHistorikk: [BudLinjeJS] = []
    var hoyesteBud: BudLinjeJS?
    var budgiver: Int?
    var trumf: String?
    var trumfNavn: String?
    var onsket: KortJS?
    var onsketLagt = false
    var erAmerikaner = false
    var erSolo = false
    var makkerAvslort = false
    var makker: Int?
    var bordet: [SpiltJS] = []
    var sisteStikk: [SpiltJS] = []
    var sisteStikkVinner: Int?
    var stikkNummer = 0
    var antallStikkIRunden = 0
    var vrakAntall: Int?
    var trumfValg: [TrumfValgJS]?
    var kanUtenOnske = false
    var makkerplikt = false
    var utspillsplikt = false
    var sisteRunde: RundeJS?
    var vinner: Int?
    var partiFerdig = false
    var trener = TrenerStatsJS()   // rundens trenerstatistikk (til oppsummeringen)
    var forslagNokkel: String?     // satt når mennesket er i tur – klienten
                                   // henter /forslag når den endrer seg
    var loggNavn: String?
}

// MARK: - Den innebygde siden (alt inline – ingen eksterne avhengigheter)

private let webSideHTML = #"""
<!doctype html>
<html lang="nb">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Amerikaneren</title>
<style>
:root{--filt:#17603c;--filt2:#0f4a2d;--moerk:#0c2b1c;--panel:#ffffff14;--gull:#f0c75e;--roed:#c0392b;--trener:#6fd3ff}
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Segoe UI',system-ui,sans-serif;color:#f2f2ea;min-height:100vh;
     background:radial-gradient(ellipse at 50% 30%,var(--filt),var(--filt2) 70%,var(--moerk))}
header{display:flex;align-items:center;gap:16px;padding:10px 18px;background:#00000042;flex-wrap:wrap}
h1{font-size:1.2rem;letter-spacing:.5px;white-space:nowrap}
#infolinje{font-size:.88rem;opacity:.92;flex:1;min-width:220px}
#poengtavle{display:flex;gap:8px}
.poengboks{background:var(--panel);border:1px solid #ffffff2a;border-radius:8px;padding:4px 10px;text-align:center;min-width:84px}
.poengboks.aktiv{outline:2px solid var(--gull)}
.pnavn{font-size:.7rem;opacity:.85;white-space:nowrap}
.ppoeng{font-size:1.15rem;font-weight:700}
.pstikk{font-size:.66rem;opacity:.75}
main{max-width:1180px;margin:0 auto;padding:10px 14px 26px}
#bordwrap{display:grid;grid-template-columns:1fr 280px;gap:12px}
#bord{position:relative;background:#0000002e;border:1px solid #ffffff22;border-radius:16px;min-height:400px;padding:8px}
.sete{position:absolute;text-align:center;background:var(--panel);border:1px solid #ffffff26;border-radius:10px;padding:6px 10px;min-width:128px}
.sete.aktiv{outline:2px solid var(--gull);box-shadow:0 0 14px #f0c75e55}
#sete1{left:10px;top:50%;transform:translateY(-50%)}
#sete2{left:50%;top:8px;transform:translateX(-50%)}
#sete3{right:10px;top:50%;transform:translateY(-50%)}
.snavn{font-weight:600;font-size:.85rem}
.sinfo{font-size:.72rem;opacity:.85}
.merker{font-size:.7rem;color:var(--gull);min-height:1em}
#stikkbord{position:absolute;left:50%;top:54%;transform:translate(-50%,-50%);
           display:grid;grid-template-columns:92px 92px 92px;grid-template-rows:106px 106px 106px;place-items:center}
.stikkplass{display:flex;flex-direction:column;align-items:center;gap:2px;font-size:.68rem}
#stikkmidt{font-size:.78rem;opacity:.85;text-align:center;line-height:1.4}
.kort{display:inline-flex;flex-direction:column;justify-content:space-between;width:56px;height:80px;
      background:#fdfdf6;color:#1c1c24;border:1px solid #9a9a92;border-radius:7px;padding:4px 5px;
      font-weight:700;cursor:default;user-select:none;position:relative;box-shadow:0 2px 4px #00000055;
      transition:transform .1s}
.kort .kr{font-size:.95rem;line-height:1}
.kort .kf{font-size:1.3rem;align-self:flex-end;line-height:1}
.kort.roed{color:var(--roed)}
.kort.klikkbar{cursor:pointer}
.kort.klikkbar:hover{transform:translateY(-8px)}
.kort.doed{opacity:.4}
.kort.valgt{outline:3px solid var(--gull);transform:translateY(-12px)}
.kort.mini{width:40px;height:56px;padding:2px 4px}
.kort.mini .kf{font-size:1rem}
.etterlystmerke{position:absolute;bottom:-7px;left:50%;transform:translateX(-50%);
                background:var(--gull);color:#402b05;font-size:.55rem;border-radius:4px;padding:0 3px;white-space:nowrap}
#haand{display:flex;flex-wrap:wrap;gap:6px;justify-content:center;padding:16px 4px 4px;min-height:100px}
#fasepanel{margin-top:12px;background:#00000038;border:1px solid #ffffff22;border-radius:12px;
           padding:10px 14px;text-align:center;min-height:58px}
button{font:inherit;background:var(--gull);color:#3a2a05;border:0;border-radius:8px;padding:7px 14px;
       font-weight:700;cursor:pointer;margin:3px}
button:hover{filter:brightness(1.08)}
button:disabled{opacity:.4;cursor:default}
button.sekundaer{background:#ffffff2b;color:#f2f2ea}
#side{display:flex;flex-direction:column;gap:12px}
.boks{background:#00000038;border:1px solid #ffffff22;border-radius:12px;padding:10px 12px}
.boks h3{font-size:.78rem;text-transform:uppercase;letter-spacing:.8px;opacity:.8;margin-bottom:6px}
#budliste{list-style:none;font-size:.82rem;line-height:1.5}
#sistestikk{display:flex;gap:4px;flex-wrap:wrap;align-items:center;font-size:.75rem}
#overlay{position:fixed;inset:0;background:#000000a8;display:flex;align-items:center;justify-content:center;z-index:50}
#overlayboks{background:#123c26;border:1px solid #ffffff33;border-radius:16px;padding:26px 34px;
             max-width:520px;text-align:center;box-shadow:0 10px 40px #000c}
#overlayboks h2{margin-bottom:10px}
#overlayboks table{margin:12px auto;border-collapse:collapse;font-size:.9rem}
#overlayboks td{padding:2px 12px;text-align:left}
#overlayboks th{padding:2px 12px;font-size:.72rem;opacity:.75;text-align:left}
.skjult{display:none!important}
#melding{position:fixed;left:50%;bottom:18px;transform:translateX(-50%);background:#a33;color:#fff;
         padding:8px 16px;border-radius:8px;z-index:60;max-width:80vw}
.anbefalt{outline:3px solid var(--trener)!important;box-shadow:0 0 14px #6fd3ffaa!important}
.kort.anbefalt.valgt{outline:3px solid var(--gull)!important}
#trenerinnhold{font-size:.82rem;line-height:1.55}
#trenerinnhold .dim{opacity:.6}
.trenerrad{display:flex;justify-content:space-between;gap:10px}
.trenerrad .tall{font-variant-numeric:tabular-nums;opacity:.9}
.trenerrad.topp{color:var(--trener);font-weight:700}
#trenertabell td{padding:1px 8px 1px 0;font-size:.8rem}
.tenker{display:inline-block;animation:puls 1s infinite}
@keyframes puls{50%{opacity:.35}}
@media (max-width:900px){#bordwrap{grid-template-columns:1fr}#side{flex-direction:row}#side .boks{flex:1}}
</style>
</head>
<body>
<header>
  <h1>🇺🇸 Amerikaneren</h1>
  <div id="infolinje">Laster …</div>
  <div id="poengtavle"></div>
  <button class="sekundaer" id="trenerknapp" onclick="toggleTrener()">💡 Trener: på</button>
  <button class="sekundaer" onclick="if(confirm('Starte nytt parti?'))post('/nyttParti')">Nytt parti</button>
</header>
<main>
  <section id="bordwrap">
    <div id="bord">
      <div class="sete" id="sete1"></div>
      <div class="sete" id="sete2"></div>
      <div class="sete" id="sete3"></div>
      <div id="stikkbord"></div>
    </div>
    <aside id="side">
      <div class="boks" id="trenerboks"><h3>💡 Trener</h3><div id="trenerinnhold"></div></div>
      <div class="boks"><h3>Budrunden</h3><ul id="budliste"></ul></div>
      <div class="boks"><h3>Siste stikk</h3><div id="sistestikk"></div></div>
    </aside>
  </section>
  <section id="fasepanel">Kobler til …</section>
  <section id="haand"></section>
</main>
<div id="overlay" class="skjult"><div id="overlayboks"></div></div>
<div id="melding" class="skjult"></div>
<script>
'use strict';
let T = null, sisteJson = '', forrigeFase = '';
let valgteVrak = new Set(), valgtTrumf = null;
let F = null, forslagHenter = false;
let trenerPaa = localStorage.getItem('trener') !== 'av';

function fornavn(t, s){ return t.navn[s].split(' ')[0]; }

// Treneren: forslaget hentes asynkront (beregningen tar opp mot et
// tidsbudsjett), og er gyldig når nøkkelen matcher /state.
function forslagAktiv(t){ return trenerPaa && t && t.dinTur && F && F.nokkel === t.forslagNokkel; }

function sjekkForslag(){
  if (!trenerPaa || !T || !T.dinTur || !T.forslagNokkel) return;
  if (F && F.nokkel === T.forslagNokkel) return;
  hentForslag();
}

async function hentForslag(){
  if (forslagHenter) return;
  forslagHenter = true;
  try {
    const r = await fetch('/forslag');
    if (r.ok){ const f = await r.json(); F = f.aktuelt ? f : null; }
  } catch (e){}
  forslagHenter = false;
  render();
  sjekkForslag();   // tilstanden kan ha rukket å gå videre
}

function toggleTrener(){
  trenerPaa = !trenerPaa;
  localStorage.setItem('trener', trenerPaa ? 'paa' : 'av');
  if (trenerPaa) sjekkForslag();
  render();
}

function kortHtml(k, kl, attr, ekstra){
  kl = kl || ''; attr = attr || ''; ekstra = ekstra || '';
  const rang = k.tekst.slice(0, -1);
  return `<div class="kort ${k.roed ? 'roed ' : ''}${kl}" ${attr}>` +
         `<span class="kr">${rang}</span><span class="kf">${k.farge}</span>${ekstra}</div>`;
}

function oppdater(t){
  const j = JSON.stringify(t);
  if (j === sisteJson) return;
  sisteJson = j; T = t;
  if (t.fase !== forrigeFase){ valgteVrak.clear(); valgtTrumf = null; forrigeFase = t.fase; }
  render();
  sjekkForslag();
}

function render(){
  const t = T; if (!t) return;
  renderTopp(t); renderSeter(t); renderStikkbord(t);
  renderSide(t); renderTrener(t); renderFasepanel(t); renderHaand(t); renderOverlay(t);
}

function renderTrener(t){
  const knapp = document.getElementById('trenerknapp');
  knapp.textContent = trenerPaa ? '💡 Trener: på' : '💡 Trener: av';
  knapp.style.outline = trenerPaa ? '2px solid var(--trener)' : '';
  document.getElementById('trenerboks').classList.toggle('skjult', !trenerPaa);
  if (!trenerPaa) return;
  const el = document.getElementById('trenerinnhold');
  if (!t.dinTur){
    el.innerHTML = '<span class="dim">Venter på din tur …</span>';
    return;
  }
  if (!forslagAktiv(t)){
    el.innerHTML = '<span class="tenker">💭</span> Treneren tenker …';
    return;
  }
  let html = '';
  if (F.fase === 'budrunde'){
    html = `Anbefalt bud: <b>${F.bud.tekst}</b>`;
  } else if (F.fase === 'byttekort'){
    html = '<div style="margin-bottom:4px">Anbefalt vrak:</div>' +
      '<div style="display:flex;gap:4px;flex-wrap:wrap">' +
      F.vrak.map(k => kortHtml(k, 'mini')).join('') + '</div>';
  } else if (F.fase === 'velgTrumf'){
    html = `Anbefalt trumf: <b>${F.trumf} ${F.trumfNavn}</b>` +
      (F.onsket ? `, etterlys <b>${F.onsket.tekst}</b>` : ' – uten etterlysning');
  } else if (F.fase === 'spill'){
    html = `Anbefalt kort: <b>${F.kort.tekst}</b>`;
    if (F.rangering && F.rangering.length > 1){
      html += ` <span class="dim">· EV over ${F.verdener} verdener</span>`;
      html += F.rangering.map((r, i) =>
        `<div class="trenerrad${i === 0 ? ' topp' : ''}"><span>${r.kort.tekst}` +
        (r.likeverdige.length > 1 ? ` <span class="dim">+${r.likeverdige.length - 1} likeverdige</span>` : '') +
        `</span><span class="tall">${r.verdi.toFixed(2)}</span></div>`).join('');
    } else if (F.rangering && F.rangering.length === 1 && F.rangering[0].likeverdige.length > 1){
      html += ' <span class="dim">(likeverdige kort – valget er gitt)</span>';
    }
  }
  el.innerHTML = html;
}

function renderTopp(t){
  const deler = [`Runde ${t.runde}`, `Først til ${t.maalPoeng} poeng`];
  if (t.trumf) deler.push(`Trumf ${t.trumf} ${t.trumfNavn}`);
  if (t.erAmerikaner) deler.push('AMERIKANER!');
  if (t.erSolo) deler.push('SOLO-AMERIKANER!');
  if (t.onsket) deler.push(`Etterlyst ${t.onsket.tekst}${t.onsketLagt ? ' (lagt)' : ''}`);
  if (t.hoyesteBud && t.fase !== 'budrunde' && !t.erAmerikaner && !t.erSolo)
    deler.push(`Bud: ${t.hoyesteBud.tekst} (${fornavn(t, t.hoyesteBud.sete)})`);
  if (t.trumf && !t.erSolo){
    if (t.makkerAvslort && t.makker != null) deler.push(`Makker: ${fornavn(t, t.makker)}`);
    else if (t.onsket && t.haand.some(k => k.id === t.onsket.id)) deler.push('Du er makkeren (hemmelig)!');
    else deler.push('Makkeren er hemmelig');
  }
  document.getElementById('infolinje').textContent = deler.join(' · ');
  document.getElementById('poengtavle').innerHTML = t.navn.map((n, i) =>
    `<div class="poengboks${t.aktivSete === i ? ' aktiv' : ''}"><div class="pnavn">${n}</div>` +
    `<div class="ppoeng">${t.poeng[i]}</div><div class="pstikk">${t.stikkTatt[i]} stikk</div></div>`).join('');
}

function renderSeter(t){
  for (const s of [1, 2, 3]){
    const el = document.getElementById('sete' + s);
    const merker = [];
    if (t.budgiver === s) merker.push('🎯 budgiver');
    else if (t.fase === 'budrunde' && t.hoyesteBud && t.hoyesteBud.sete === s) merker.push('💬 ' + t.hoyesteBud.tekst);
    if (t.makkerAvslort && t.makker === s) merker.push('🤝 makker');
    if (t.aktivSete === s && t.aiTenker) merker.push('<span class="tenker">🤔 tenker…</span>');
    el.innerHTML = `<div class="snavn">${t.navn[s]}</div>` +
      `<div class="sinfo">${t.antallKort[s]} kort · ${t.stikkTatt[s]} stikk</div>` +
      `<div class="merker">${merker.join(' · ')}</div>`;
    el.classList.toggle('aktiv', t.aktivSete === s);
  }
}

function stikkCelle(t, sete, vis, dimmet){
  const spilt = vis.find(x => x.sete === sete);
  if (!spilt) return '<div class="stikkplass"></div>';
  return `<div class="stikkplass"${dimmet ? ' style="opacity:.45"' : ''}>` +
         kortHtml(spilt.kort) + `<span>${fornavn(t, sete)}</span></div>`;
}

function renderStikkbord(t){
  const vis = t.bordet.length ? t.bordet : t.sisteStikk;
  const dimmet = !t.bordet.length;
  let midt = '';
  if (t.fase === 'spill') midt = `Stikk ${t.stikkNummer}/${t.antallStikkIRunden}`;
  if (dimmet && vis.length && t.sisteStikkVinner != null) midt += `<br>→ ${fornavn(t, t.sisteStikkVinner)}`;
  document.getElementById('stikkbord').innerHTML =
    `<div></div>${stikkCelle(t, 2, vis, dimmet)}<div></div>` +
    `${stikkCelle(t, 1, vis, dimmet)}<div id="stikkmidt">${midt}</div>${stikkCelle(t, 3, vis, dimmet)}` +
    `<div></div>${stikkCelle(t, 0, vis, dimmet)}<div></div>`;
}

function renderSide(t){
  document.getElementById('budliste').innerHTML =
    t.budHistorikk.map(b => `<li>${fornavn(t, b.sete)}: ${b.tekst}</li>`).join('') ||
    '<li style="opacity:.6">Ingen bud ennå</li>';
  const ss = document.getElementById('sistestikk');
  ss.innerHTML = t.sisteStikk.length
    ? t.sisteStikk.map(x => kortHtml(x.kort, 'mini')).join('') +
      `<span>→ ${fornavn(t, t.sisteStikkVinner)}</span>`
    : '<span style="opacity:.6">–</span>';
}

function venter(hvem, hva){ return `<span class="tenker">🤔</span> ${hvem} ${hva} …`; }

function renderFasepanel(t){
  const el = document.getElementById('fasepanel');
  const hvem = t.aktivSete != null ? fornavn(t, t.aktivSete) : '';
  let html = '';
  if (t.fase === 'budrunde'){
    if (t.dinTur){
      const hoyeste = t.hoyesteBud
        ? `Høyeste bud: ${t.hoyesteBud.tekst} (${fornavn(t, t.hoyesteBud.sete)})` : 'Ingen bud ennå';
      const anbBud = forslagAktiv(t) && F.bud ? F.bud.id : null;
      html = `<div style="margin-bottom:6px">${hoyeste} – ditt bud:</div>` +
        t.lovligeBud.map(b =>
          `<button class="${b.id === anbBud ? 'anbefalt' : ''}" onclick="giBud('${b.id}')">${b.tekst}</button>`).join('');
    } else html = venter(hvem, 'vurderer budet');
  } else if (t.fase === 'byttekort'){
    if (t.dinTur){
      html = `<div style="margin-bottom:6px">Du vant budrunden og har tatt opp talongen – ` +
        `velg ${t.vrakAntall} kort å vrake (de forblir skjult for de andre).</div>` +
        `<button ${valgteVrak.size === t.vrakAntall ? '' : 'disabled'} onclick="sendVrak()">` +
        `Vrak valgte (${valgteVrak.size}/${t.vrakAntall})</button>`;
    } else html = venter(hvem, 'tar opp talongen og vraker');
  } else if (t.fase === 'velgTrumf'){
    if (t.dinTur){
      html = `<div style="margin-bottom:6px">Velg trumf${t.erSolo
        ? ' (solo: etterlysning er valgfri)'
        : ' og etterlys et kort – den som har det blir makkeren din'}.</div>`;
      const fAktiv = forslagAktiv(t);
      html += t.trumfValg.map(v =>
        `<button class="${valgtTrumf === v.farge ? '' : 'sekundaer'}` +
        `${fAktiv && F.trumf === v.farge ? ' anbefalt' : ''}" ` +
        `${(!t.kanUtenOnske && !v.kandidater.length) ? 'disabled' : ''} ` +
        `onclick="velgFarge('${v.farge}')">${v.farge} ${v.navn}</button>`).join('');
      if (valgtTrumf){
        const v = t.trumfValg.find(x => x.farge === valgtTrumf);
        if (v.kandidater.length){
          html += `<div style="margin-top:8px;font-size:.85rem">Etterlys:</div>` +
            `<div style="display:flex;gap:5px;justify-content:center;flex-wrap:wrap;margin-top:5px">` +
            v.kandidater.map(k => kortHtml(k,
              'mini klikkbar' + (fAktiv && F.onsket && F.onsket.id === k.id ? ' anbefalt' : ''),
              `onclick="sendTrumf('${k.id}')"`)).join('') +
            `</div>`;
        }
        if (t.kanUtenOnske)
          html += `<button class="sekundaer${fAktiv && F.trumf && !F.onsket ? ' anbefalt' : ''}" ` +
            `onclick="sendTrumf(null)">Uten etterlysning</button>`;
      }
    } else html = venter(hvem, 'velger trumf');
  } else if (t.fase === 'spill'){
    if (t.dinTur){
      html = 'Din tur – klikk kortet du vil spille.';
      if (t.utspillsplikt) html += '<div style="font-size:.8rem;opacity:.85;margin-top:4px">' +
        'Utspillsplikt: første stikk åpnes i trumf, så det etterlyste kortet tvinges fram.</div>';
      if (t.makkerplikt) html += '<div style="font-size:.8rem;opacity:.85;margin-top:4px">' +
        'Makkerplikt: du må legge det etterlyste kortet.</div>';
    } else html = venter(hvem, 'tenker');
  } else if (t.fase === 'rundeFerdig' || t.fase === 'spillFerdig'){
    html = 'Runden er ferdig.';
  }
  el.innerHTML = html;
}

function renderHaand(t){
  const fAktiv = forslagAktiv(t);
  document.getElementById('haand').innerHTML = t.haand.map(k => {
    let kl = '', attr = '';
    if (t.fase === 'spill' && t.dinTur){
      if (t.lovligeKort.includes(k.id)){ kl = 'klikkbar'; attr = `onclick="spillKort('${k.id}')"`; }
      else kl = 'doed';
      if (fAktiv && F.kort && F.kort.id === k.id) kl += ' anbefalt';
    } else if (t.fase === 'byttekort' && t.dinTur){
      kl = 'klikkbar' + (valgteVrak.has(k.id) ? ' valgt' : '');
      if (fAktiv && F.vrak && F.vrak.some(v => v.id === k.id)) kl += ' anbefalt';
      attr = `onclick="toggleVrak('${k.id}')"`;
    }
    const merke = (t.onsket && k.id === t.onsket.id)
      ? '<span class="etterlystmerke">etterlyst</span>' : '';
    return kortHtml(k, kl, attr, merke);
  }).join('');
}

function renderOverlay(t){
  const ov = document.getElementById('overlay'), boks = document.getElementById('overlayboks');
  if (t.fase !== 'rundeFerdig' && t.fase !== 'spillFerdig'){ ov.classList.add('skjult'); return; }
  let html = t.fase === 'spillFerdig'
    ? `<h2>🏆 ${t.navn[t.vinner]} vant partiet!</h2>`
    : `<h2>Runde ${t.runde} er ferdig</h2>`;
  const r = t.sisteRunde;
  if (r){
    const lag = fornavn(t, r.budgiver) + (r.makker != null ? ' + ' + fornavn(t, r.makker) : '');
    html += `<p>${lag} tok ${r.stikkLaget} stikk på ${r.budTekst} – ${r.klarte ? 'klarte det ✓' : 'røk ✗'}</p>`;
    html += '<table><tr><th></th><th>Stikk</th><th>+/−</th><th>Sum</th></tr>' +
      t.navn.map((n, i) =>
        `<tr><td>${n}</td><td>${r.stikkPerSpiller[i]}</td>` +
        `<td>${r.poengEndring[i] >= 0 ? '+' : ''}${r.poengEndring[i]}</td>` +
        `<td><b>${t.poeng[i]}</b></td></tr>`).join('') + '</table>';
  }
  if (trenerPaa && t.trener && t.trener.totalt){
    const s = t.trener;
    html += `<p style="margin-top:10px">💡 Du fulgte treneren i <b>${s.fulgt}</b> av <b>${s.totalt}</b> valg.</p>`;
    if (s.avvik.length){
      const fasenavn = { budrunde: 'Bud', byttekort: 'Vrak', velgTrumf: 'Trumf', spill: 'Spill' };
      html += '<table id="trenertabell"><tr><th>Fase</th><th>Du valgte</th><th>Treneren</th></tr>' +
        s.avvik.map(a => `<tr><td>${fasenavn[a.fase] || a.fase}</td>` +
          `<td>${a.valgt}</td><td>${a.forslag}</td></tr>`).join('') + '</table>';
    }
  }
  html += t.fase === 'rundeFerdig'
    ? `<button onclick="post('/nesteRunde')">Neste runde</button>`
    : `<button onclick="post('/nyttParti')">Nytt parti</button>`;
  if (t.fase === 'spillFerdig' && t.loggNavn)
    html += `<p style="font-size:.72rem;opacity:.75;margin-top:8px">Etterprøvbar spillogg: ` +
      `<a href="/logg/${t.loggNavn}" target="_blank" style="color:#9fd7ff">${t.loggNavn}</a></p>`;
  boks.innerHTML = html;
  ov.classList.remove('skjult');
}

async function post(sti, kropp){
  try {
    const r = await fetch(sti, { method: 'POST', headers: { 'Content-Type': 'application/json' },
                                 body: JSON.stringify(kropp || {}) });
    const t = await r.json();
    if (t.feil){ visMelding(t.feil); return; }
    if (t.fase) oppdater(t);
  } catch (e){ visMelding('Mistet kontakten med tjeneren.'); }
}
function giBud(id){ post('/bud', { action: id }); }
function toggleVrak(id){
  if (valgteVrak.has(id)) valgteVrak.delete(id);
  else if (valgteVrak.size < T.vrakAntall) valgteVrak.add(id);
  render();
}
function sendVrak(){ post('/vrak', { kort: [...valgteVrak] }); valgteVrak.clear(); }
function velgFarge(f){ valgtTrumf = f; render(); }
function sendTrumf(id){ const b = { suit: valgtTrumf }; if (id) b.onsket = id; post('/trumf', b); }
function spillKort(id){ post('/spill', { kort: id }); }
function visMelding(tekst){
  const m = document.getElementById('melding');
  m.textContent = tekst; m.classList.remove('skjult');
  clearTimeout(m._t); m._t = setTimeout(() => m.classList.add('skjult'), 3200);
}
async function poll(){
  try { const r = await fetch('/state'); if (r.ok) oppdater(await r.json()); } catch (e){}
  setTimeout(poll, 450);
}
poll();
</script>
</body>
</html>
"""#

import Foundation

/// Heuristikkvektene i MesterAI og håndvurderingen, samlet i én injiserbar
/// og serialiserbar struktur. Standardverdiene er de historiske håndsatte
/// konstantene – med `MesterVekter()` er oppførselen bit-for-bit som før.
/// Evolusjonssøket (`Amerikaneren evolusjon`) muterer disse feltene og
/// spiller kandidatene mot hverandre; vekter per instans gjør at fire ulike
/// kandidater kan sitte ved samme bord.
struct MesterVekter: Codable, Equatable {
    // MARK: estimerStikk – håndvurderingen bak bud, trumfvalg og budvekting
    var trumfPerKort = 0.55       // grunnverdi per trumfkort
    var trumfLengdeBonus = 0.4    // tillegg per trumfkort over tre
    var essTrumf = 1.0            // ess i trumffargen
    var essSide = 0.9             // ess i sidefarge
    var kongeStøttet = 0.65       // konge med minst ett følgekort
    var kongeSingel = 0.3         // singel konge
    var dameStøttet = 0.35        // dame i minst tre-korts farge
    var dameSingel = 0.15         // dame med tynn støtte
    var renonsFaktor = 0.45       // renons × min(2, antall trumf)
    var singeltonBonus = 0.3      // singelton i sidefarge

    // MARK: budVekt – hvor hardt samplede verdener vektes mot budhistorikken
    var alleEksp = 0.5            // straff-eksponent for Amerikaner-meldere
    var alleSlingring = 2.0       // slingringsmonn før straffen slår inn
    var tallEksp = 0.6            // straff-eksponent for tallbud
    var tallSlingring = 2.5       // slingringsmonn (est + dette ≥ budet)
    var passEksp = 0.4            // straff-eksponent for pass-signalet
    var passMakkerTillegg = 2.0   // antatt makkerbidrag i pass-vurderingen
    var passSlingring = 1.5      // slingringsmonn før pass-straffen

    // MARK: velgBud – EV-formingen i budrunden
    var soloTerskelSlingring = 2.5   // hvor nær «alle stikk» solo simuleres
    var soloDesperasjonLette = 1.5   // desperasjon senker soloterskelen
    var byttekortEstimat = 0.4       // forventet løft per byttekort
    var passTrygghet = 1.5           // trygghetsbonus til pass-alternativet
    var budDesperasjon = 0.6         // desperasjon premierer tallbud
    var budTrygghet = 0.4            // trygghet straffer marginale tallbud
    var amerikanerDesperasjon = 0.10 // desperasjonstillegg for Amerikaner
    var soloDesperasjon = 0.15       // desperasjonstillegg for solo
    var desperasjonSkala = 2.0       // hvor fort avstand i poeng gir utslag

    // MARK: vurder – poengmålingen per samplet verden i kortspillet
    var motstanderBasis = 1.0     // grunnvekt for motstandernes poeng
    var motstanderNevner = 3.0    // deler: (basis + nærhet) / nevner

    /// Genene for evolusjonssøket: navn, felt og typisk skala (mutasjons-
    /// steg er en andel av skalaen, så små og store vekter muteres jevnt).
    static let gener: [(navn: String, sti: WritableKeyPath<MesterVekter, Double>, skala: Double)] = [
        ("trumfPerKort", \.trumfPerKort, 0.55),
        ("trumfLengdeBonus", \.trumfLengdeBonus, 0.4),
        ("essTrumf", \.essTrumf, 1.0),
        ("essSide", \.essSide, 0.9),
        ("kongeStøttet", \.kongeStøttet, 0.65),
        ("kongeSingel", \.kongeSingel, 0.3),
        ("dameStøttet", \.dameStøttet, 0.35),
        ("dameSingel", \.dameSingel, 0.15),
        ("renonsFaktor", \.renonsFaktor, 0.45),
        ("singeltonBonus", \.singeltonBonus, 0.3),
        ("alleEksp", \.alleEksp, 0.5),
        ("alleSlingring", \.alleSlingring, 2.0),
        ("tallEksp", \.tallEksp, 0.6),
        ("tallSlingring", \.tallSlingring, 2.5),
        ("passEksp", \.passEksp, 0.4),
        ("passMakkerTillegg", \.passMakkerTillegg, 2.0),
        ("passSlingring", \.passSlingring, 1.5),
        ("soloTerskelSlingring", \.soloTerskelSlingring, 2.5),
        ("soloDesperasjonLette", \.soloDesperasjonLette, 1.5),
        ("byttekortEstimat", \.byttekortEstimat, 0.4),
        ("passTrygghet", \.passTrygghet, 1.5),
        ("budDesperasjon", \.budDesperasjon, 0.6),
        ("budTrygghet", \.budTrygghet, 0.4),
        ("amerikanerDesperasjon", \.amerikanerDesperasjon, 0.10),
        ("soloDesperasjon", \.soloDesperasjon, 0.15),
        ("desperasjonSkala", \.desperasjonSkala, 2.0),
        ("motstanderBasis", \.motstanderBasis, 1.0),
        ("motstanderNevner", \.motstanderNevner, 3.0),
    ]

    /// Gaussisk mutasjon: hvert gen flyttes med sannsynlighet `rate`,
    /// med standardavvik `sigma` × genets skala. Negative vekter er lov
    /// (evolusjonen får ombestemme seg om fortegn), men nevneren holdes
    /// unna null så vurder() aldri deler på ingenting.
    func mutert<R: RandomNumberGenerator>(
        sigma: Double, rate: Double, rng: inout R
    ) -> MesterVekter {
        var barn = self
        for gen in Self.gener where Double.random(in: 0..<1, using: &rng) < rate {
            let støy = gaussisk(&rng) * sigma * gen.skala
            barn[keyPath: gen.sti] += støy
        }
        barn.motstanderNevner = max(0.5, abs(barn.motstanderNevner))
        return barn
    }

    /// Uniform krysning: hvert gen arves fra en tilfeldig av foreldrene.
    static func krysning<R: RandomNumberGenerator>(
        _ a: MesterVekter, _ b: MesterVekter, rng: inout R
    ) -> MesterVekter {
        var barn = a
        for gen in gener where Bool.random(using: &rng) {
            barn[keyPath: gen.sti] = b[keyPath: gen.sti]
        }
        return barn
    }

    private func gaussisk<R: RandomNumberGenerator>(_ rng: inout R) -> Double {
        // Box–Muller; u holdes unna 0 for log-en.
        let u = max(Double.random(in: 0..<1, using: &rng), 1e-12)
        let v = Double.random(in: 0..<1, using: &rng)
        return (-2 * Foundation.log(u)).squareRoot() * cos(2 * .pi * v)
    }
}

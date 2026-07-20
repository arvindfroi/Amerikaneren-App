# 🇺🇸 Amerikaneren

En iOS-app for det norske kortspillet **Amerikaner**, bygget i SwiftUI.
Utseendet er inspirert av *Brain Training* (Dr. Kawashima), CPU-motstanderne er
Civilization-aktige lederprofiler basert på ekte historiske figurer fra
amerikansk historie, og kampanjen er bygget opp som *Punch-Out!!* – du bokser
deg oppover ligaene til tittelkampen mot selveste **Onkel Sam**.

## Funksjoner

| # | Funksjon | Beskrivelse |
|---|----------|-------------|
| 0 | **Onboarding & tutorial** | Skippbar onboarding der Benjamin Franklin 👴🪁 er læremester, med en seks-stegs interaktiv regelgjennomgang med eksempelkort. Kan hentes fram igjen fra hovedmenyen. |
| 1 | **Online** | Fullt vert/klient-spill over Game Center (2–4 mennesker, CPU-er fyller tomme seter). Verten kjører motoren som autoritet; hver spiller ser kun sin egen hånd. Faller noen fra, tar en CPU over. Krever Game Center-oppsett i App Store Connect. |
| 🏆 | **Ranked** | Elo-rating med divisjoner (Borger → … → President). Matchmaking via Game Center `playerGroup` gjør at du kun møter spillere i din egen divisjon. K=64 de første 10 kampene, så K=32. Rating, historikk og divisjon vises i statistikken; toppliste via Game Center-ledertavle. |
| 2 | **Offline** | Fullt spillbart mot 3 CPU-er med fire vanskelighetsgrader (Lett / Middels / Vanskelig / President). Hver CPU har Civ-stil «agenda» og egenskaper som styrer budgivningen og trumfbruken (man bløffer lite i Amerikaner, så bløff-trekket betyr bevisst lite). På President-nivå spiller alle perfekt – personligheten skrus av. |
| 3 | **Companion-modus** | Digital poengblokk for når dere spiller med ekte kort: 3–6 spillere, automatisk poengutregning (inkl. Amerikaner-meldinger og makkerlag), runde-for-runde-historikk, og lagring rett inn i statistikken. |
| 4 | **Statistikk & H2H** | Seiersprosent, rekker, budtreff, snittbud, Amerikaner-forsøk, stikk per runde, partier per modus – pluss detaljert head-to-head per rival: innbyrdes score, snittmargin, største seier, formkurve (siste 5) og full møtehistorikk. |
| 🥊 | **Kampanje** | Punch-Out-struktur: Bronseligaen → Sølvligaen → Gulligaen → Tittelkampen. Hver kamp har et scenario (poengforsprang, budkrav, sprint/maraton) og pre/post-kamp-replikker. |

## Reglene som er implementert

Basert på [Wikipedia](https://no.wikipedia.org/wiki/Amerikaner_(kortspill)) og
[kortregler.no](https://kortregler.no/amerikaner):

- 4 spillere, hele kortstokken deles ut (13 kort hver). Ess høyest, to lavest.
- **Budrunde** fra 5 til 13 stikk; pass er lov, bud må overby. Meldingen
  **«Amerikaner»** (alle 13 stikk alene, uten trumf og makker) slår alle tallbud.
- Budvinneren **velger trumf og ber om et kort** (typisk høy trumf) – den som
  har kortet blir hemmelig makker og *må* legge det ved første lovlige
  anledning i første stikk.
- Følg farge; høyeste trumf vinner stikket, ellers høyeste kort i utspillsfargen.
- **Poeng:** Klarer laget budet får begge budets verdi, feiler de trekkes den.
  Øvrige spillere får ett poeng per stikk. Amerikaner gir ±52.
- **Først til 52** vinner. Ved likhet vinner budgiversiden fra siste runde.

## Motstandergalleriet

🥉 George Washington · Benjamin Franklin · Thomas Jefferson
🥈 Abraham Lincoln · Theodore Roosevelt · Franklin D. Roosevelt
🥇 John F. Kennedy · Ronald Reagan · Donald Trump · Dwight D. Eisenhower
🏆 **Onkel Sam** – sluttbossen som spiller feilfritt

## Teste uten Mac (Windows/Linux)

### Kjernen i terminalen: MesterAI og companion uten Apple-utstyr

Spillmotoren, MesterAI/NevroHjerne, Elo og companion-poengføringen er ren
Foundation-Swift og bygger med SwiftPM på Linux og Windows (WSL) – helt
uten Xcode. `Package.swift` i rota definerer kjernemodulen pluss et
kommandolinjeverktøy:

```bash
# Swift 5.9+ (swift.org, swiftly, eller docker run -it swift:6.0)
swift test                          # motor-, AI-, Elo- og companion-tester
swift build -c release

.build/release/Amerikaneren spill --navn Dere,Navn    # SPILL SELV: 2 mennesker + 2 President-AI-er (hot-seat)
.build/release/Amerikaneren demo --seed 42            # se MesterAI spille, stikk for stikk
.build/release/Amerikaneren arena --partier 10 --mot vanskelig   # mål styrken over mange partier
.build/release/Amerikaneren companion                 # før poeng for et fysisk parti i terminalen
.build/release/Amerikaneren hjelp                     # alle kommandoer og flagg
```

**Uten å installere noe som helst:** CI-en kjører det samme på hver push –
Linux-jobben («Linux – kjernetester og MesterAI i aksjon») skriver en
komplett MesterAI-demokamp, en miniarena med seiersprosenter og en
companion-demo rett i jobbsammendraget (Actions-fanen → siste kjøring
→ Summary).

### Hele appen i nettleseren (simulatorbygg)

CI-en bygger appen ved hver push og legger ut et **simulatorbygg** som
artifact (Actions-fanen → siste kjøring → `Amerikaneren-simulator`).

To måter å spille det i nettleseren via [appetize.io](https://appetize.io):

1. **Manuelt:** last ned artifactet og last det opp på
   [appetize.io/upload](https://appetize.io/upload) (gratis konto holder).
2. **Automatisk:** opprett en Appetize-konto, hent API-nøkkelen, og legg
   den inn som GitHub-secret `APPETIZE_API_TOKEN`
   (Settings → Secrets and variables → Actions). CI laster da opp hvert
   bygg og skriver spillelenken i jobbsammendraget. Legg i tillegg inn
   `APPETIZE_PUBLIC_KEY` (fra første opplasting) for å beholde samme
   lenke hver gang.

Merk: Game Center (online/ranked) virker ikke i simulator – det krever
ekte enhet via TestFlight og App Store Connect-oppsett.

## Bygg og kjør

Prosjektet bruker [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
cd Amerikaneren-App
xcodegen generate
open Amerikaneren.xcodeproj
```

Velg `Amerikaneren`-skjemaet og kjør på simulator eller enhet (iOS 17+).
Kjør enhetstestene (spillmotor + AI) med **⌘U**.

For onlinespill: skru på Game Center-capability for din egen bundle-id i
App Store Connect (entitlements-filen ligger klar).

## Dokumentasjon

- [docs/DESIGN.md](docs/DESIGN.md) – designsystemet (tokens, komponenter, motion) og UX-prinsippene (bestemor-testen, tommelsonen)
- [docs/ARKITEKTUR.md](docs/ARKITEKTUR.md) – lagdeling, dataflyt, persistens og designvalg
- [docs/REGLER.md](docs/REGLER.md) – reglene slik de er implementert, med kilder og bevisste avvik
- [docs/AI.md](docs/AI.md) – hvordan CPU-ene vurderer hånden, byr og spiller, per vanskelighetsgrad
- [docs/UTVIKLINGSLOGG.md](docs/UTVIKLINGSLOGG.md) – hva som er gjort og hva som gjenstår

## Arkitektur

```
Amerikaneren/
├── App/           Inngang, hovedmeny, global tilstand + persistens (JSON)
├── Engine/        Ren spillmotor (tilstandsmaskin) – ingen UI-avhengigheter
├── AI/            Heuristisk AI: håndvurdering, bud, kortvalg, personlighet
├── Opponents/     Lederprofilene (Civ-stil) med replikker (Punch-Out-stil)
├── Campaign/      Kretser, scenarioer og fremdrift
├── Game/          Spillebord, kort, budpanel, oppsummeringer
├── Online/        Game Center-manager + lobby
├── Companion/     Poengføring for fysiske partier (logikken er UI-fri)
├── Stats/         Modeller, aggregering og H2H-visninger
└── Theme/         Brain Training-designspråket (papir, blekk, maskot)
CLI/               Kommandolinjeverktøy: MesterAI-demo, arena og companion
Tests/             Enhetstester for motor, AI og companion-poengføring
Package.swift      SwiftPM-manifest – kjernen bygger på Linux/WSL uten Xcode
```

Spillmotoren (`GameEngine`) er bevisst UI-fri og deterministisk (seedbar
utdeling), slik at reglene er enhetstestet og gjenbrukbare for online-verten.
Det samme gjelder companion-poengføringen (`CompanionParti`), som deles
mellom appen, kommandolinjeverktøyet og testene.

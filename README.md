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
├── Companion/     Poengføring for fysiske partier
├── Stats/         Modeller, aggregering og H2H-visninger
└── Theme/         Brain Training-designspråket (papir, blekk, maskot)
Tests/             Enhetstester for motor og AI
```

Spillmotoren (`GameEngine`) er bevisst UI-fri og deterministisk (seedbar
utdeling), slik at reglene er enhetstestet og gjenbrukbare for online-verten.

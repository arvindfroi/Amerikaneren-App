# 🇺🇸 Amerikaneren

En iOS-app for det norske kortspillet **Amerikaner**, bygget i SwiftUI.
Utseendet er inspirert av *Brain Training* (Dr. Kawashima), CPU-motstanderne er
Civilization-aktige lederprofiler basert på parodier av amerikanske presidenter
og ikoner, og kampanjen er bygget opp som *Punch-Out!!* – du bokser deg oppover
ligaene til tittelkampen mot selveste **Onkel Sam**.

> Alle figurer er parodi.

## Funksjoner

| # | Funksjon | Beskrivelse |
|---|----------|-------------|
| 0 | **Onboarding & tutorial** | Skippbar onboarding med maskoten «Professor Duke» 🦆🎩 og en seks-stegs interaktiv regelgjennomgang med eksempelkort. Kan hentes fram igjen fra hovedmenyen. |
| 1 | **Online** | Game Center-lobby med matchmaking (2–4 spillere) og en Codable meldingsprotokoll (`OnlineMessage`) over `GKMatch`. Krever Game Center-oppsett i App Store Connect. |
| 2 | **Offline** | Fullt spillbart mot 3 CPU-er med fire vanskelighetsgrader (Lett / Middels / Vanskelig / President). Hver CPU har Civ-stil «agenda» og egenskaper (aggresjon, risiko, bløff, lojalitet, storhetsdrøm) som faktisk styrer bud- og spillestilen. |
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

## Motstandergalleriet (parodi)

🥉 Georg Vaskington · Ben Franklyn · Tomas Jeffersen
🥈 Abraham Linkoln · Teddy Rosebilt · F.D. Rooseweldt
🥇 J.F. Kennedylund · Ronny Reagansen · Dwight Eisenhauger
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

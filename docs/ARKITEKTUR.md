# Arkitektur

Appen er en SwiftUI-app for iOS 17+ uten tredjepartsavhengigheter.
Prosjektfilen genereres med XcodeGen fra `project.yml`.

## Lagdeling

```
┌─────────────────────────────────────────────────────┐
│  SwiftUI-views (Game/, Campaign/, Companion/, …)    │
│  – tegner tilstand, sender brukerhandlinger videre  │
├─────────────────────────────────────────────────────┤
│  ViewModels (GameViewModel, CompanionViewModel)     │
│  – @MainActor, driver AI-turer, oversetter til UI   │
├─────────────────────────────────────────────────────┤
│  GameEngine (Engine/)          AIPlayer (AI/)       │
│  – ren tilstandsmaskin         – ren heuristikk     │
│  – ingen UI-avhengigheter, ingen async              │
├─────────────────────────────────────────────────────┤
│  AppState + JSON-persistens (App/, Stats/)          │
└─────────────────────────────────────────────────────┘
```

Prinsippet er at **all spillogikk ligger i `GameEngine`** og er synkron,
deterministisk (seedbar kortstokk) og enhetstestet. UI-laget stiller bare
spørsmål (`lovligeKort(for:)`, `lovligeBud(for:)`) og melder handlinger
(`spill(kort:seat:)`, `giBud(seat:action:)`). Motoren validerer alt selv,
så et view aldri kan sette spillet i ugyldig tilstand.

## Mappene

| Mappe | Innhold |
|-------|---------|
| `Engine/` | `Card`/`Suit`/`Rank`/`Deck` (kortmodell), `Bid` (meldinger), `GameEngine` (faser: budrunde → trumfvalg → stikkspill → poeng). |
| `AI/` | `AIDifficulty` (Lett/Middels/Vanskelig/President), `AIPersonality` (Civ-trekk), `AIPlayer` (håndvurdering, bud- og kortvalg). |
| `Opponents/` | `Opponent` (lederprofil med replikker) og `OpponentRoster` (hele galleriet av historiske figurer). |
| `Campaign/` | `CampaignStage`/`CampaignCircuit` (statisk kampanjedata), `CampaignProgress` (opplåsing), views for kart og pre-kamp. |
| `Game/` | `GameViewModel` (limet mellom motor, AI og UI), spillebord, kortvisninger, budpanel, oppsummeringer. |
| `Companion/` | Poengføring for fysiske partier – gjenbruker poengreglene, men uten motor (dere spiller jo med ekte kort). |
| `Stats/` | `MatchRecord`/`RoundRecord` (rådata per parti), `AggregatedStats` og `HeadToHead` (beregnes på nytt fra rådataene hver gang), views. |
| `Online/` | `GameCenterManager` (innlogging, matchmaking, `OnlineMessage`-protokoll over `GKMatch`) og lobby-view. |
| `App/` | Inngang, hovedmeny, `AppState` (global tilstand + persistens). |
| `Theme/` | Hele designspråket: farger, fonter, `BTButtonStyle`, `PapirPanel`, `SnakkeBoble`, portretter, `TrekkLinje`. |
| `Tests/` | Enhetstester for motor og AI. |

## Dataflyt i et offline-parti

1. `OfflineOppsettView` lager en `GameViewModel` med tre `Opponent`-er
   (mennesket sitter alltid på sete 0).
2. `GameViewModel.startSpill()` kaller `engine.startRunde()` og starter
   `aiLøkke()` – en async Task som spør motoren hvem som er i tur, lar
   riktig `AIPlayer` velge handling, og legger inn små pauser så bordet
   føles levende.
3. Menneskets trykk går via `menneskeByr/menneskeVelgerTrumf/menneskeSpiller`,
   som validerer mot motoren og vekker AI-løkka igjen.
4. Når motoren melder `rundeFerdig`/`spillFerdig` viser viewmodellen
   oppsummering, og ved partislutt bygges en `MatchRecord` som
   `AppState.registrerParti` lagrer.

## Persistens

Bevisst enkelt: `Codable` + JSON-filer i appens Documents-mappe
(`partier.json`, `kampanje.json`) og `UserDefaults` for småting
(onboarding-flagg, spillernavn). Statistikk **lagres aldri aggregert** –
`AggregatedStats` og `HeadToHead` beregnes fra rå `MatchRecord`-er ved
behov, så nye statistikkfelter kan legges til uten migrering.

## Kampanjescenarioer

Scenario-modifikatorer (`motstanderStartPoeng`, `målPoeng`, `kravMinsteBud`)
håndteres i `GameViewModel`, ikke i motoren: forsprang legges som en
justering utenpå `engine.scores`, og budkravet sjekkes mot rundehistorikken.
Motoren forblir dermed ren standard-Amerikaner.

## Online-design

Vert/klient over `GKMatch`, implementert i `Online/`:

- **Vertsvalg:** Spilleren med lavest `gamePlayerID` er vert – deterministisk
  likt på alle enheter, ingen forhandling nødvendig.
- **Autoritet:** Kun verten kjører `GameEngine`. Klientene har ingen motor;
  de tegner `OnlineSnapshot`-er og sender `OnlineAction`-er. Verten
  validerer alle handlinger mot motoren, så en klient kan verken spille
  ulovlig eller utgi seg for et annet sete (setet utledes av avsenderen).
- **Skjult informasjon:** Snapshots er personaliserte – hver spiller får
  kun sin egen hånd og sine lovlige trekk, og `makkerSeat` sendes først
  når makkeren er avslørt. Ingen klient har data den ikke skal se.
- **CPU-utfyllere:** Med 2–3 mennesker fyller verten setene med CPU-er fra
  motstandergalleriet og driver dem i samme AI-løkke som offline.
- **Frafall:** Kobler en spiller fra, erstatter verten setet med en CPU og
  spillet fortsetter. Faller verten fra, avsluttes partiet hos klientene.
- **Statistikk:** Ved partislutt sender verten hele rundehistorikken; hver
  enhet lagrer sin egen `MatchRecord` med seg selv som «meg», så H2H
  fungerer mot både venner (Game Center-id) og CPU-utfyllere.

Flyt: lobby (`OnlineView`) → verten trykker start → `OnlineSetup` per
spiller → snapshots etter hver handling → rundeoppsummering (verten går
videre) → partislutt (alle lagrer statistikk).

## Ranked og Elo

`Ranked/Elo.swift` inneholder divisjonene (`RankTier`) og den rene
kalkulatoren (`EloCalculator`) – begge enhetstestet.

- **Matchmaking i kategori:** divisjonen settes som `playerGroup` på
  `GKMatchRequest`; Game Center matcher kun spillere med samme gruppe,
  så en Senator aldri møter en Borger i ranked.
- **Ratingutveksling:** hver klient sender en `hello`-melding med egen
  rating når matchen er funnet; verten legger alle ratinger i
  `OnlineSetup.seatRating`.
- **Desentralisert beregning:** hver enhet beregner kun sin egen delta
  (parvis Elo mot de tre andre, egen K-faktor), lagrer den lokalt i
  `AppState` og rapporterer ny rating til Game Center-ledertavlen.
  Ingen server trengs – input (ratinger + sluttpoeng) er identisk hos
  alle, så resultatene er konsistente.
- CPU-utfyllere har fast rating etter vanskelighetsgrad, så et delvis
  CPU-bord fortsatt kan rates.

## Haptikk og lyd

`Theme/Feedback.swift` er ett samlingspunkt for all sanselig feedback
(UIKit-generatorene + systemlyder som plassholdere). Spillhendelser
kaller `Feedback.kortSpilt()`, `.stikkAvgjort(mitt:)`, `.dinTur()` osv.;
brukerens av/på-valg lagres i UserDefaults og respekteres ved hvert kall.

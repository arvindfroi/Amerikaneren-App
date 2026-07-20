# Utviklingslogg

## v0.13 – Regelfiks: første stikk åpnes i trumf

- Feil funnet under spilltesting i CLI-et: budvinneren kunne spille ut
  en annen farge enn trumf i første stikk, og da slapp den som satt med
  det etterlyste kortet å legge det – makkeren kunne forbli hemmelig,
  i strid med husreglene. Slik skal det være: budvinneren åpner første
  stikk i trumffargen (det er slik trumfen «vises» fysisk), alle følger
  farge, og makkeren tvinges dermed til å legge det etterlyste kortet i
  første stikk.
- Rettet i selve motoren (`GameEngine.lovligeKort`: utspillsplikt for
  budvinneren i første stikk), så app-UI, online og CLI håndhever
  regelen samme sted. Fallback: har budvinneren ingen trumf, står
  utspillet fritt (og makkerplikten gjelder som før ved første lovlige
  anledning).
- Speilet i MesterAI-søkeren (`Spillregler.lovligMaske`), som simulerer
  alle verdener/planer med samme plikt – bud-, vrak- og trumfvurderingen
  regner nå riktig på at makkeren alltid avsløres i første stikk. Ny
  slutning i `Spillinnsikt`: åpner budgiveren utenom trumf, er
  budgiveren beviselig renons i trumf.
- Ny motortest for utspillsplikten + re-verifisering i den
  egenskapsbaserte testen og i `harness motorfuzz`. CLI-et forklarer
  plikten når et menneske sitter som budvinner.
- Merk: gamle rundeopptak der budvinneren åpnet utenom trumf avvises nå
  ved avspilling/import (ulovlig trekk) – og NevroHjerne-vektene bør
  trenes om på selvspill under de rettede reglene. Plan med kommandoer
  og målte størrelser: `docs/RETRENING.md`.

## v0.12 – Grenene samlet

- Parallellgrenen `claude/flawless-game-bot-2qez2n` (v0.9–v0.10 under)
  flettet inn i main, som fra før hadde v0.11-arbeidet. Konflikten sto i
  companion-modus: den omarbeidede view-modellen (bordmodus, lagring,
  spillerregister) vant, mens den UI-frie `CompanionParti` består som
  poengkjerne for CLI-et og testene – nå koblet til motorens navngitte
  satser og kortfordeling (`GameRules`), så reglene har én kilde.
- SwiftPM-modulen utvidet: `Innsamling/`, `Stats/Records.swift`,
  `SpillerRegister.swift` og `Spillestil.swift` bygger og testes nå
  også på Linux (view-modell-testene kjøres fortsatt kun i Xcode).

## v0.11 – Kjernen uten Mac: SwiftPM, CLI og companion-logikk på Linux

Forberedende arbeid for å kunne teste companion-modus og se MesterAI i
aksjon uten Mac eller iPhone:

- **SwiftPM-manifest** (`Package.swift`): motor, AI (MesterAI +
  NevroHjerne), Elo og companion-poengføring bygger nå som én modul
  (`Amerikaneren`) på Linux/WSL/macOS. Testene bruker samme
  `@testable import Amerikaneren` som i Xcode-prosjektet, så ingen
  testfiler måtte endres. Verifisert med Swift 6.0.3 på Ubuntu 24.04:
  alle 44 tester grønne.
- **Kommandolinjeverktøy** (`CLI/`): `demo` spiller et helt parti med
  stikk-for-stikk-logg (seedbar), `arena` måler MesterAI mot valgfritt
  nivå over mange partier (seiersprosent, budtreff, snittrunder), og
  `companion` er poengblokken i terminalen – interaktiv eller som
  scriptet demo. Setene styres med samme fallback-mønster som testene
  (Mester → heuristikk → første lovlige).
- **Companion-logikken trukket ut av UI-et**: ny UI-fri `CompanionParti`
  (`Companion/CompanionScoring.swift`) eier poengreglene og
  navnevalideringen; `CompanionViewModel` er nå bare skjematilstand som
  delegerer. Ny testfil `CompanionScoringTests` dekker tallbud,
  Amerikaner (±mål/2, ±mål/4), solo (±mål), makker-kanttilfeller og
  3/6-spillervarianter.
- **CI**: ny Linux-jobb (`swift:6.0-noble`-container) kjører
  kjernetestene på hver push og legger en MesterAI-demokamp, en
  miniarena og companion-demoen rett i jobbsammendraget – MesterAI kan
  dermed inspiseres «in action» i nettleseren uten noe lokalt oppsett.
- Målt i denne sandkassen (tid 0.05 s/trekk): MesterAI vant 3 av 4
  partier mot tre «Middels» med 85 % budtreff som budgiver.
- **Hot-seat-spill i terminalen** (`spill`-kommandoen): mennesker og
  AI-er om hverandre ved samme tastatur – f.eks. 2 mennesker mot 2
  President-AI-er. Hendene skjules ved at skjermen tømmes når tastaturet
  bytter spiller; alle valg (bud, vrak, trumf, etterlysning, kort) går
  via nummererte menyer, så en «1»-strøm spiller alltid lovlig – det
  brukes som røyktest i CI.

## v0.10 – Companion-modus omarbeidet (portert fra parallellgren)

- **Minimal føring**: per runde registreres bare budvinner, budtype,
  makker og motstandernes stikk – lagets stikk, om budet holdt og alle
  poengene regnes ut automatisk, med kontrolllinje før runden føres.
- **Fleksible partier**: spill til valgfritt mål eller åpent parti som
  avsluttes når som helst; 3–6 spillere med riktig kortfordeling
  (17/1, 12/4, 10/2, 8/4). Angreknapp for feiltasting, og pågående parti
  lagres fortløpende så appen kan lukkes midt i kvelden.
- **Spillerregister** (`RegistrertSpiller`): faste profiler for folk du
  spiller fysisk med, som kan kobles til Game Center-brukere – da telles
  fysiske og online-partier mot samme person sammen i H2H.
- `GameRules` fikk navngitte poengsatser (budgiverFaktor/amerikanerPoeng/
  soloAmerikanerPoeng) som motoren og companion deler, og generalisert
  kortfordeling for 3–6 spillere. 15 nye companion-tester (kjøres i CI)
  + regeloppsett-test; poengreglene er identiske med motorens.
- Grunnlaget er companion-arbeidet fra grenen
  `claude/companion-mode-tricks-mgk2jp` (parallelt spor), tilpasset
  motoren og husreglene i main.
- **Bordmodus**: mobilen ligger flatt på bordet som poengtavle hele
  kvelden (skjermen holdes våken), og hver runde føres med ~6 store
  trykk i bordets tre naturlige øyeblikk: budrunden avgjort (navn +
  bud/AMERIKANER/SOLO som kjempeknapper), ønskekortet lagt (ett trykk
  på makkeren – stikk ført på feil person nullstilles automatisk), og
  runden ferdig (ett trykk rett på stikktallet per motstander).
  Utfallet vises for kontroll før føring, neste runde starter av seg
  selv på første spørsmål, og en påbegynt runde overlever at appen
  drepes. 6 nye flyt-tester (21 companion-tester totalt).
- **Full sporing + spillestilanalyse**: rådata-typene skilt ut i
  `Stats/Records.swift` (Foundation-rene) med nye felter – rundevarighet,
  valgfri trumf i companion, poengmål per parti, utledet lagstikk.
  Ny `Stats/Spillestil.swift`: **Budanalyse** («Budskolen») dømmer
  budgivningen mot MesterAI-referansen (~89 % klaring) på klaringsrate
  og margin, med poeng-lagt-igjen/tapt i klartekst, og **Makkerpar**
  viser hvem som faktisk lykkes sammen – på tvers av fysiske og
  digitale partier. Vises i statistikken; 8 nye tester (kjører også på
  Linux).

## v0.9 – Datainnsamling, backend og treningsverktøy i repo

- **Partiopptak**: motoren husker utdelingen gjennom runden, og hver
  ferdig runde kan fanges som et rått `Rundeopptak` (utdeling, budrunde,
  vrak, trumf, alle 48 spilte kort, resultat) som spilles av og
  regel-verifiseres trekk for trekk før det får bli data. Helt anonymt:
  aldri navn eller ID-er, kun «menneske/CPU-nivå» per sete og dato.
- **Innsamling med samtykke** (av som standard, ny bryter i
  innstillingene): avgrenset kø på disk, batch-opplasting med
  reprise-sikkerhet, giftige filer forkastes, køen slettes om samtykket
  trekkes. Offline, kampanje og online (verten) dekkes.
- **Backend-kode klar** i `Backend/valtown/` (Val Town/Deno + SQLite):
  strukturell validering, idempotent lagring, døgn-nødbrems,
  NDJSON-eksport for treneren. Hostingvalg utsatt – 5-minutters
  deploy-oppskrift i Backend/README.md; appen samler lokalt inntil
  endepunktet settes.
- **Treningsverktøyene inn i repoet** (`Tools/trainer`, `Tools/harness`)
  med symlenker til app-kildene – pipelinen overlever nå utenfor
  utviklingsmiljøet. Ny `trainer importer` (innsamlede partier →
  treningsdatasett, med full re-verifisering; tuklede partier avvises)
  og `trainer syntetisk` (testdata i appens format). Kjeden testet
  ende-til-ende.
- **AI-veikart** i docs/AI.md: makker-modellering via policy-vekting,
  åpent konvensjonslag, per-makker ferdighet, ekspert-iterasjon 2 og
  nett-prior i søket. docs/DATA.md beskriver dataformat og personvern.
- 4 nye tester (opptak-rundtur, tukle-avvisning, JSON-rundtur, kø);
  27 totalt.

## v0.8 – Husregler, byttekort, solo-amerikaner og nevralt nett

- **Regelverket omlagt til eierens husregler**: byttekort-talong (12 kort
  + 4 til budvinneren, skjult vrak), først til 100, Amerikaner med makker
  og trumf (±50/±25), ny solo-amerikaner-melding (±100, valgfri
  etterlysning), budvinner får alltid 2× makkerens sats, og forbud mot å
  etterlyse vrakede kort. Alternativt partiformat med fast rundetall
  (`GameRules.maksRunder`). Companion, online-protokoll, UI og tutorials
  fulgt opp.
- **MesterAI utvidet**: vrak-søk med simulerte kandidater, sampling som
  modellerer den skjulte vrakhaugen, budvekting av verdener mot
  budhistorikken, matchbevisst budgivning (varians når man ligger bak
  sent), maskinvare-skalert søk og solo-uttrekkslogikk.
- **NevroHjerne**: tre MLP-hoder (bud/vrak/spill) i ren Swift, destillert
  fra 800 lærer-selvspillpartier og RL-finjustert med partiseier som
  belønning, verdihode og destillasjonsanker. Sluttport på 2 000 ferske
  runder valgte det destillerte nettet (selvspill-gevinsten overførte
  ikke – porten fungerte). Vektene skipes innebygd; nettet foreslår vrak
  i søket og er reservespiller.
- **Målt (komplett system)**: 83 % seier i hele partier mot tre
  «Vanskelig» (25 % = likt spill), 7,96 mot 5,22 poeng per runde, 89 %
  kontrakter som budgiver. Egenskapsbasert motorfuzz verifiserer alle
  poengregler uavhengig; 23 tester i CI.

## v0.7 – MesterAI: søkebot på President-nivå

- **MesterAI** (`AI/MesterAI.swift`, `MesterVerden.swift`,
  `MesterSolver.swift`): President-vanskelighetsgraden drives nå av ekte
  søk i stedet for heuristikk – determinisert Monte Carlo over samplede
  verdener, eksakt dobbeltdummy-løsning av sluttspillet (alfa-beta med
  transposisjonstabell og sekvensreduksjon) og simuleringsbasert
  budgivning/trumfvalg på forventet poengsum. Ingen juks: boten ser bare
  det setet lovlig vet, inkludert renons- og makkerplikt-slutninger.
- Løseren er verifisert mot en brute-force-minimax på 800 tilfeldige
  stillinger, og hele runder fuzz-testes for lovlighet. Målt mot tre
  «Vanskelig»-heuristikker vinner MesterAI 50 % av hele partier (mot
  15 % for en «Vanskelig» i samme sete) og klarer 93 % av egne
  kontrakter. Tall og metode i docs/AI.md.
- `AIPlayer` ruter President-beslutninger til MesterAI og beholder
  heuristikken som sikkerhetsnett; øvrige nivåer er uendret.

## v0.6 – Designsystem og tommelsone-UX

- **Designsystem (`DS`)**: tokens for farge, typografi (Dynamic
  Type-skalert), avstand, radius, trykkflate-mål og tre motion-kurver.
  `Theme` er nå en fasade over tokens. Dokumentert i docs/DESIGN.md.
- **Tommelsone-ergonomi**: bud- og trumfpanelene flyttet fra midten av
  skjermen ned til rett over hånden – all interaksjon i et helt parti
  skjer i nederste tredjedel (portrett først).
- **Bestemor-vennlig kortspilling**: nytt delt `HandActionArea` for
  offline og online – trykk for å velge (kortet løftes), trykk igjen,
  dra opp ELLER bruk den store «Spill kortet»-knappen. To-trinns valg
  hindrer uhell; hver gest har knapp-ekvivalent; accessibility-labels
  på kortene.
- «Store kort»-innstilling, større minimum trykkflater (48/54 pt) og
  monospaced sifre i poengvisninger.

## v0.5 – Ranked, haptikk/lyd og spillflyt

- **Ranked-modus med Elo:** divisjoner tematisert som politisk karriere
  (Borger → Ordfører → Senator → Guvernør → Visepresident → President).
  Divisjonen brukes som Game Center `playerGroup`, så matchmaking kun
  skjer innen samme kategori. Parvis Elo for fire spillere, K=64 de
  første ti kampene (kalibrering), deretter K=32. CPU-utfyllere har fast
  rating etter vanskelighetsgrad. Rating rapporteres til Game
  Center-ledertavlen `amerikaneren.elo` (må opprettes i App Store
  Connect). Ratinghistorikk vises i statistikken.
- **Haptikk og lyd** (`Theme/Feedback.swift`): kort lagt, stikk avgjort,
  din tur, bud, Amerikaner-melding, runde-/partislutt. Kan skrus av i
  det nye innstillingsarket (tannhjulet i hovedmenyen). Lydene er
  systemlyder som plassholdere til egne lydfiler kommer med de øvrige
  ressursene.
- **Spillflyt:** lengre pause mellom stikkene så alle rekker å se det
  siste kortet, «X tok stikket»-banner, replikker som forsvinner av seg
  selv etter 4 sekunder, og fjærende animasjoner på kortene inn på
  bordet. Samme flyt offline og online.
- Innstillingsark: navn, lyd av/på, haptikk av/på, divisjonsstatus.
- Enhetstester for Elo-beregningen (symmetri, nullsum, K-faktor,
  divisjonsgrenser).

## v0.4 – Online ende-til-ende

- Vert/klient-spill over Game Center: verten (lavest gamePlayerID) kjører
  `GameEngine` som eneste autoritet, klientene speiler personaliserte
  snapshots og sender handlinger.
- Skjult informasjon bevart online: hver spiller mottar kun egen hånd,
  egne lovlige trekk, og makkeren avsløres først når ønskekortet legges.
- 2–4 mennesker per bord; CPU-er fra motstandergalleriet fyller tomme
  seter, og en CPU tar over hvis noen kobler fra midt i partiet.
- Online-partier lagres i statistikken på hver enhet (verten sender full
  rundehistorikk ved partislutt), så H2H fungerer mot venner.
- Nytt online-spillebord (`OnlineTableView`) med samme designspråk som
  offline-bordet.

## v0.3 – Dokumentasjon og finpuss

- Dokumentasjon: `docs/ARKITEKTUR.md`, `docs/REGLER.md`, `docs/AI.md`.
- Spillebordet viser budlagets fremdrift («Budlaget: 4/7») basert på
  offentlig kjent informasjon – uavslørt makkers stikk telles ikke.
- Statistikk: favorittrumf (mest valgte trumffarge som budgiver) og
  snittpoeng per parti.
- Ryddet opp i AI-ens lagforståelse (`erPåMittLag`): eksplisitt modell av
  hvem som vet hva før og etter at makkeren er avslørt.

## v0.2 – Ekte figurer, Trump og AI-balanse

- Byttet parodinavn til ekte historiske figurer med ekte hjemsteder;
  Benjamin Franklin erstattet maskoten «Professor Duke» som læremester.
- Ny CPU: Donald Trump («Trumfmesteren») med kampanjekampen «Kunsten å by»
  i Gulligaen – maks aggresjon, melder Amerikaner ved første anledning.
- AI-balanse etter spilltesting-innspill:
  - Bløff nedtonet til nesten ingenting (man bløffer lite i Amerikaner).
  - Personlighet styrer primært budgivning og trumfbruk.
  - President-vanskelighetsgrad spiller perfekt – personligheten skrus av.
  - President kan velges i offline-oppsettet.

## v0.1 – Første versjon

- Komplett spillmotor etter reglene fra Wikipedia/kortregler.no:
  budrunde (5–13 + Amerikaner), trumfvalg med hemmelig makker og
  makkerplikt, stikkspill, poeng, først til 52.
- Offline-spill mot 3 CPU-er, fire vanskelighetsgrader, Civ-inspirerte
  lederprofiler med Punch-Out-replikker.
- Kampanje i fire kretser med scenarioer og opplåsing, tittelkamp mot
  Onkel Sam.
- Skippbar onboarding og seks-stegs tutorial.
- Companion-modus for poengføring av fysiske partier (3–6 spillere).
- Detaljert statistikk og head-to-head, alt beregnet fra rå partidata.
- Game Center-lobby med matchmaking og meldingsprotokoll (online-spillet
  ende-til-ende er neste byggetrinn).
- Brain Training-inspirert designspråk, XcodeGen-oppsett, enhetstester.

## Kjente hull / neste steg

- [ ] App Store Connect-oppsett: registrere appen, skru på Game Center
      for bundle-id-en, og opprette ledertavlen `amerikaneren.elo`
      (kreves før online/ranked kan testes på ekte enheter).
- [ ] Første bygg i Xcode – koden er skrevet uten Mac tilgjengelig, så
      det kan dukke opp kompileringsfeil som må rettes.
- [ ] Egne lydfiler (systemlyder er plassholdere i dag) + app-ikon og
      tegnede portretter (stil à la Brain Training).
- [ ] Online: rematch-knapp og invitasjon av spesifikke venner
      (`GKMatchmakerViewController` støtter det – bare UI som mangler).
- [ ] Sesonger/nullstilling av rating og topplistevisning i appen
      (GKGameCenterViewController for ledertavlen).
- [ ] Byttekort-varianten (valgfri regel hos kortregler.no).
- [ ] Motorstøtte for 3/5/6 spillere (companion dekker det i dag).
- [ ] Lokalisering (alt er norsk i dag) og støtte for mørk modus.
- [ ] TestFlight-runde med ekte spilltesting av AI-balansen.

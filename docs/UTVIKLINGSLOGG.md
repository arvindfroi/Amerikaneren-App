# Utviklingslogg

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

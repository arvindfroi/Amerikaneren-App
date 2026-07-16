# Utviklingslogg

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

- [ ] Online: koble vert/klient-flyten mot `GameEngine` (protokollen finnes).
- [ ] Byttekort-varianten (valgfri regel hos kortregler.no).
- [ ] Motorstøtte for 3/5/6 spillere (companion dekker det i dag).
- [ ] Lyd og haptikk.
- [ ] App-ikon og ekte portretter (tegnet stil à la Brain Training).

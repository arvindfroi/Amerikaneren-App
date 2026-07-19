# Slik tenker CPU-ene

AI-en har tre lag. Lett, Middels og Vanskelig bruker ren heuristikk i
`AI/AIPlayer.swift` – rask, forutsigbar å teste og lett å justere.
**President**-nivået bruker søkeboten **MesterAI** (`AI/MesterAI.swift` med
`MesterVerden.swift` og `MesterSolver.swift`) sammen med det nevrale
nettet **NevroHjerne** (`AI/NevroNett.swift`), begge beskrevet nederst.

## Håndvurdering (`estimerStikk`)

For hver mulige trumffarge estimeres forventede stikk:

- **Trumflengde**: ~0,55 stikk per trumfkort, med bonus over 3 kort
  (lengde er viktigere enn honnører i Amerikaner).
- **Honnører**: Ess ≈ 1 stikk (0,9 utenfor trumf), konge 0,65 med dekning,
  dame 0,35 i lange farger.
- **Renons/singelton** i sidefarger gir stjålne stikk skalert mot antall
  trumf på hånden.

`besteTrumf` velger fargen med høyest estimat.

## Budgivning (`velgBud`)

```
estimat = håndestimat + 2.0 (forventet makkerbidrag)
        + (aggresjon − 0.5) × 2.5     ← hoppes over på President
        + støy fra vanskelighetsgrad   ← hoppes over på President
```

Byr laveste lovlige tallbud så lenge det er ≤ eget estimat, ellers pass.

- **Amerikaner-melding** (alle stikk med makker) krever estimat nær
  full pott pluss et personlighetsslag mot `storhetsdrøm`; solo-
  amerikaner meldes bare med estimat over alle stikkene. På President
  simuleres begge på forventet poengsum i stedet.
- **Bløff**: bevisst nesten borte – man bløffer lite i Amerikaner. Kun en
  sjelden (`bløff × 0,15`) overbydning på ett hakk. Aldri på President.

## Kortvalg (`velgKort`)

Prioritering når man ikke spiller ut:

1. Makkeren har stikket → legg lavest (lojalitet ≥ 0,35 eller President;
   sistemann gjør det alltid).
2. Kan vinne → legg **billigste vinnende kort**. Risikovillige (< President)
   kan tidlig i runden gamble på å spare et ess.
3. Ellers → legg lavest (trumf regnes alltid som dyrest å kaste).

Utspill:

- **Budgiverlaget trekker trumf** de første rundene – hvor lenge styres av
  `risiko` (3–5 stikk); på President trekkes trumf så lenge motstanderne
  faktisk har trumf igjen (enkel kortteling på spilte kort).
- Deretter spilles sikre vinnere: ess, eller kort som er blitt høyest i
  fargen fordi alt over er spilt (kortteling).
- Ellers lavest.

## Vanskelighetsgrader

| Grad | Budstøy | Feilspillsjanse | Personlighet |
|------|---------|-----------------|--------------|
| Lett | ±2,2 | 35 % tilfeldig lovlig kort | full effekt |
| Middels | ±1,2 | 15 % | full effekt |
| Vanskelig | ±0,5 | 4 % | full effekt |
| **President** | 0 | 0 | **skrus helt av** – MesterAI overtar |

President-regelen er absolutt: `AIDifficulty.spillerPerfekt` kortslutter
alle personlighetsjusteringer og ruter alle beslutninger til MesterAI.
Heuristikken står igjen som sikkerhetsnett om søket skulle feile.

## Personligheter (Civ-stil)

Trekkene (0–1) vises i lederprofilen og styrer primært **budgivning og
trumfbruk** – ikke fusk eller skjult informasjon. AI-en ser aldri andres
kort; den vet bare hva som er spilt (åpen informasjon rundt bordet).

| Trekk | Effekt |
|-------|--------|
| Aggresjon | Skyver budestimatet opp/ned |
| Risiko | Hvor lenge laget trekker trumf; gambling med storkort |
| Bløff | Sjelden overbydning – liten effekt med vilje |
| Lojalitet | Om man legger lavt når makkeren har stikket |
| Storhetsdrøm | Sannsynligheten for å melde Amerikaner |

Eksempler: Theodore Roosevelt (aggresjon 0,95) byr over evne, Donald Trump
(aggresjon 1,0 + storhetsdrøm 1,0) melder Amerikaner ved første anledning,
George Washington (bløff 0,0) byr aldri uten dekning, Eisenhower
(risiko 0,2) spiller konservativt og planmessig.

## Lagforståelse

`erPåMittLag` bruker kun informasjon setet faktisk har: budgiver er kjent
for alle, en avslørt makker likeså, mens en **uavslørt makker** vet selv at
den er på budgiverlaget – forsvarerne behandler den som medspiller inntil
ønskekortet legges. Ingen AI vet noe et menneske i samme sete ikke ville
visst.

## MesterAI – søkeboten bak President-nivået

MesterAI jukser aldri: den ser bare det setet lovlig kan se, samlet i
`Spillinnsikt` – egen hånd, alle spilte kort, hvem som meldte hva, og
slutninger et menneske kunne trukket:

- **Renonser**: fulgte ikke et sete fargen, kan setet ikke ha den fargen.
- **Makkerplikt-slutning**: la et sete et annet kort enn det etterlyste i
  første stikk i en situasjon der plikten ville tvunget kortet fram, kan
  setet ikke ha det.
- **Ønskekortet**: budgiveren kan ikke ha det, og den som selv sitter med
  det vet at den er makker.

Beslutningene bygger på tre teknikker:

1. **Determinisert Monte Carlo** (`Spillinnsikt.sampleVerden`): de ukjente
   kortene deles ut i mange mulige verdener som respekterer alle
   begrensningene over (mest bundne kort først, vektet mot restbehov).
2. **Eksakt sluttspill** (`Dobbeltdummy`): hver verden spilles med en rask
   grådig policy fram til `eksaktStikkGrense` stikk gjenstår (standard 6);
   resten løses optimalt med alfa-beta, transposisjonstabell og
   sekvensreduksjon (nabokort blant de gjenværende er likeverdige).
   Løseren håndhever både farge-følging og makkerplikten i første stikk.
3. **Simulert budgivning** (`velgBud`): pass, laveste lovlige bud og
   Amerikaner sammenliknes på forventet poengsum over de samme samplede
   verdenene – budscenarioet spilles ut med hybrid grådig/eksakt løsning
   og tar høyde for talong-opptaket, pass-scenarioet lar den sterkeste
   motstanderen deklarere. Trumfvalget (`velgTrumfOgMakker`) simulerer
   alle fire farger og ber alltid om det høyeste **levende** trumfkortet
   laget mangler (aldri et kort budgiveren selv vraket).
4. **Simulert vrak** (`velgByttekort`): kandidat-vrak genereres for de
   beste trumffargene (behold trumf/ess, tøm korte sidefarger – pluss
   nettets forslag) og spilles ut mot samplede verdener; vraket som
   oftest berger budet vinner.

Med byttekort-varianten modellerer samplingen også vrakhaugen: for alle
andre enn budvinneren er de fire vrakede kortene ukjente og settes til
side i hver samplet verden. Det etterlyste kortet kan derimot aldri ligge
der – det er forbudt å ønske et vraket kort – så makkeren (eller
motspilleren, ved solo) finnes alltid rundt bordet.

I kortspillet måles hvert kandidatkort (etter sekvensreduksjon) over alle
verdenene: budgiverlaget maksimerer sannsynligheten for å nå budet og
deretter antall lagstikk; forsvaret det motsatte. Overstikk prioriteres
aldri foran kontrakten – akkurat som poengreglene tilsier.

Tidsbruken styres av `MesterKonfig` (verdener, sluttspillgrense og et mykt
tidsbudsjett på ~0,45 s per trekk), så President-motstanderne føles kjappe
også på eldre telefoner.

### Målt styrke

Benchmarks (release-bygg, faste frø) med sete 0 mot tre
«Vanskelig»-heuristikker, sammenliknet med en «Vanskelig» i samme sete:

- **Hele partier til 52 poeng:** MesterAI vant 20 av 40 partier (50 %),
  mot 6 av 40 (15 %) for heuristikken – med 25 % som nøytralt utgangspunkt
  for fire like spillere.
- **200 enkeltrunder:** 4,08 poeng per runde mot 3,31 for heuristikken.
  Som budgiver klarte MesterAI 26 av 28 kontrakter (93 %) med samme
  snittbud (8,2), mot 28 av 34 (82 %) for heuristikken; i forsvar felte
  den 30 av 107 kontrakter mot 24 av 106.

Dobbeltdummy-løseren er i tillegg verifisert identisk med en
brute-force-minimax på 800 tilfeldige stillinger, og hele runder
fuzz-testes for lovlighet med blandede vanskelighetsgrader.

## NevroHjerne – det nevrale nettet

Tre små MLP-er i ren Swift (`AI/NevroNett.swift`, ~100k parametre totalt,
inferens på mikrosekunder uten Core ML): et **budhode** (hva skal meldes),
et **byttehode** (hvilke 4 kort vrakes) og et **spillhode** (hvilket kort
legges). Trekkuttrekket bruker kun lovlig informasjon – egen hånd, spilte
kort, meldinger, avslørt makker, poengstilling – kodet relativt til eget
sete. Vektene ligger innebygd i `AI/NevroVekter.swift` og regenereres av
treningsharnessen.

### Trening

1. **Destillering**: 800 hele selvspill-partier med MesterAI i alle seter
   ga ~109 000 budbeslutninger, ~13 000 vrak og ~496 000 kortvalg.
   Nettene trenes veiledet med holdt-ut testsett (5 %): 91,6 % budtreff,
   77 % vraktreff og 62 % kortvalgstreff mot læreren.
2. **Forsterkningslæring**: selvspill-partier til 100 poeng der eneste
   belønning er å vinne partiet, med verdihode som baseline,
   destillasjonsanker (KL mot læreren) og deterministisk
   fremdriftsmåling mot frosne referansenett (kopispill-prinsippet fra
   turneringsbridge). RL-nettet slo referansen sin med god margin i
   selvspill (0,70 mot 0,31 poeng/runde på identiske kortstokker).
3. **Sluttport på ekte spill**: før eksport måles kandidatene på tusenvis
   av ferske, tilfeldige runder mot andre motstandertyper. Porten avslørte
   at RL-gevinsten ikke overførte fra selvspill (4,73 mot 4,82 for det
   destillerte nettet over 2 000 runder), så det destillerte nettet ble
   valgt – systemet skiper aldri selvspill-gevinster som ikke består
   møtet med virkelig spill. Fargesymmetri-augmentering (fargene er
   logisk likeverdige) er innebygd i treningen for videre iterasjoner.

### Rolle i President-boten

Nettet erstatter ikke søket – det samarbeider med det: nettets
vrakforslag prøves som egen kandidat i byttesøket (og dømmes av
simuleringen på lik linje), og nettet er reservespiller foran
heuristikken om søket skulle feile. Alene spiller nettet på ~4,8
poeng/runde mot «Vanskelig»-heuristikkene – på øyeblikkelig betenkningstid.

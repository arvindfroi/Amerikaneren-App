# Prosjekt Washington – botten som skal slå MesterAI

**Washington** er kodenavnet på neste generasjons President-bot. Målet er én
ting: spille **sterkere enn dagens MesterAI** – målt i **poeng per runde** og
**partiseier** på identiske kortstokker – innenfor samme opplevde
betenkningstid på telefon.

> Navnet passer spillets galleri: George Washington er «Grunnleggeren» som ikke
> kan lyve. Washington-botten skal grunnlegge et nytt topp­nivå – og den vinner
> ikke ved å jukse, men ved å tenke bedre om motspillerne.

> **Riktige regler (main):** det spilles **alltid med trumf**. Amerikaner = laget
> (budvinner + hemmelig makker) tar alle stikk *med trumf og makker*.
> Solo-amerikaner = alle stikk alene, **fortsatt med trumf**. Byttekort er
> standard (12 kort/hånd, budvinner vraker 4), budvinner **åpner første stikk i
> trumf**, poeng er 2× budvinner / 1× makker, først til 100. Det finnes ingen
> «alene uten trumf»-melding.

---

## 1. Hva Washington skal slå

MesterAI (`AI/MesterAI.swift` + `MesterVerden.swift` + `MesterSolver.swift` +
`NevroNett.swift`) er allerede sterk:

- Determinisert Monte Carlo med ærlige slutninger (renons, makkerplikt,
  ønskekort, byttehaug), bud-vektede verdener.
- Eksakt dobbeltdummy (alfa-beta + transposisjon + sekvensreduksjon) fra ~6
  stikk igjen; grådig utrulling før det. Verifisert mot brute-force.
- Simulert budgivning, trumf/makkerkort og vrak på forventet poengsum.
- Destillert nevralt nett (NevroHjerne) som medspiller/reserve.
- **Målt:** 7,96 poeng/runde og 83 % partiseier mot «Vanskelig»; 89 %
  kontrakter som budgiver.

Washington bygger derfor **ikke** en løser fra bunnen. Den **gjenbruker**
`Dobbeltdummy`, `Spillinnsikt/sampleVerden` og `NevroNett`, og angriper der
MesterAI beviselig er svakest.

---

## 2. Er dette bare ren matematikk? Nei.

Den eksakte dobbeltdummyen er allerede **optimal gitt én verden** – å regne «mer
matte» (flere verdener, dypere eksakt) gir bare avtagende gevinst. Ren
matematikk gjør oss *like gode* som MesterAI, ikke bedre.

Amerikaneren har **skjult informasjon og hemmelig makker**. Da vinnes spillet
ikke av å regne ut det beste trekket, men av å **gjette hva de andre har og hva
de kommer til å gjøre**. Washingtons fortrinn ligger derfor i tre ting
matematikken alene ikke gir:

1. **Slutning:** hvilke skjulte fordelinger er *egentlig* sannsynlige, gitt
   hvordan setene faktisk har spilt.
2. **Modellering:** motstanderne spiller ikke optimalt – mest mulig poeng krever
   å utnytte deres systematiske feil (ekte spilldata).
3. **Kommunikasjon:** med hemmelig makker handler halve spillet om signaler når
   matematikken sier «likegyldig».

---

## 3. MesterAIs svakheter (angrepsflaten)

| # | Svakhet | Hvorfor det koster poeng |
|---|---------|--------------------------|
| S1 | **Ingen spillhistorikk-vekting.** `sampleVerden` vekter kun mot kortantall + renons (+ bud), ikke *hvordan* setene har spilt. | Usannsynlige verdener teller like tungt som sannsynlige → dårligere slutning. |
| S2 | **Grådig utrulling for tidlige stikk.** | Åpningen – størst usikkerhet og gevinst – spilles svakest. |
| S3 | **Fast eksakt-grense (~6) + ~0,45 s/trekk, ingen pondering.** | Regnekraften mellom trekkene kastes bort; eksakt sannhet kommer sent. |
| S4 | **Ren PIMC** (ingen ISMCTS). | «Strategy fusion»: søket later som det vil kjenne skjulte kort i framtida. |
| S5 | **Nettet er kun destillert** (imitasjon); AlphaZero-loopen er ikke lukket. | Potensialet i søk-styrt trening er ubrukt. |

Crossover-måling som begrunner S3: eksakt dobbeltdummy koster &lt; 1 ms opp til 6
kort/hånd, ~9 ms median ved 8, ~50 ms ved 9. Å heve eksakt-grensen fra 6 til 8 er
nesten gratis når den ligger på en bakgrunnstråd.

---

## 4. Angrepet (prioritert etter gevinst per innsats)

Hvert punkt måles direkte mot MesterAI som sparringspartner (§5).

### A. Spillhistorikk-vekting (importance sampling) — størst enkeltgevinst
Vekt hver samplet verden med **P(de faktisk spilte kortene | verden)**, med
`NevroNett`s spillhode som motstandsmodell og en **støyparameter per
spillertype**. Utvider MesterAIs `budVekt` fra budhistorikk til spillhistorikk.
Slår S1, demper S4.

### B. Pondering + anytime-søk (utnytt motstandernes tid)
Start søket i det hånden er kjent; regn på bakgrunnstråd mens de tre andre
spiller; les av løpende beste trekk → **0 ms opplevd forsinkelse**. Ponder-hit
gjenbruker deltreet, varm transposisjonstabell. Hev `eksaktStikkGrense` 6 → 8–9
og øk antall verdener innenfor samme tidsbudsjett. Slår S3, S2.

### C. ISMCTS i stedet for ren determinisert MC
Ett søketre over informasjonsmengder, determiniseringer per utrulling. Demper S4,
gir naturlig anytime-oppførsel (passer B).

### D. Konvensjonslag for likeverdige kort
Når simuleringen sier to kort er likeverdige, velg etter en dokumentert
signal-konvensjon (høyt = styrke, lavt = svakhet). Gratis stikk-nøytral
informasjon til makkeren; boten leser samme konvensjon via A.

### E. Nett-prior i søket (AlphaZero-steget)
Spillhodets fordeling ordner/beskjærer kandidater i `velgKort`; søkets
besøksfordeling blir nye treningsmål. Lukker AlphaZero-loopen. Slår S5.

---

## 5. Målestokk (beviset)

- **Duplikat-scoring mot MesterAI:** samme seedede kortstokker spilles av begge
  boter i byttede seter; differansen i poeng/runde isolerer dyktighet fra
  kortflaks. MesterAI er baren.
- **Suksesskriterium:** poeng/runde (Washington − MesterAI) med 95 % CI helt over
  0 over ≥ 20 000 runder, og partiseier ≥ 55 % i direkte dueller.
- **CI-regresjonsvakt:** rask seedet test (Washington ≥ MesterAI) i Linux-CI-en.
- **Ærlig sluttport:** gevinster i selvspill teller ikke før de består ferske
  runder mot flere motstandertyper – samme prinsipp som NevroHjerne-treningen.

Alt drives av `SeededGenerator` og kjøres via CLI + Linux-CI («Kjernen uten
Mac»), uten Mac.

---

## 6. Gjenbruk vs. nytt

| Finnes (gjenbrukes) | Nytt i Washington |
|---------------------|-------------------|
| `Dobbeltdummy` eksakt løser | Spillhistorikk-vekting (A) i aggregeringen |
| `Spillinnsikt` + `sampleVerden` | Ponder-tråd + anytime-styring (B) |
| `NevroNett` (policy/verdi) | ISMCTS-kjerne (C) som alternativ til snitt-over-verdener |
| `MesterKonfig` (tidsbudsjett, grenser) | Konvensjonslag (D) og nett-prior-loop (E) |
| CLI + Linux-CI + duplikat-harness | Regresjonsvakt: Washington ≥ MesterAI |

---

## 7. Rekkefølge

1. **Målestokk først:** duplikat-harness Washington-vs-MesterAI + baseline → vi
   kan måle enhver endring.
2. **A – spillhistorikk-vekting** (størst gevinst, gjenbruker nett + sampler).
3. **B – pondering + hevet eksakt-grense** (lav risiko, ren ytelse).
4. **C – ISMCTS** (behold A/B som fallback og sammenlikning).
5. **D – konvensjonslag** (marginal, men gratis; hjelper også menneske-makker).
6. **E – nett-prior/AlphaZero-loop** (lengst horisont, størst tak).

Hver fase er ferdig først når duplikat-målingen mot MesterAI viser signifikant
framgang – ikke før. Når Washington beviselig slår MesterAI, kobles den inn som
det nye President-nivået (og MesterAI beholdes som frossen referanse og
regresjonsvakt).

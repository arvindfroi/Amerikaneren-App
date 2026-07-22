# Plan: slå MesterAI – neste generasjons President-bot

Mål: en ny bot («**Utfordreren**») som spiller sterkere enn dagens **MesterAI**
– målt i **poeng per runde** og **partiseier** på identiske kortstokker – og som
holder seg innenfor samme opplevde betenkningstid på telefon.

> **Riktige regler (main):** det spilles **alltid med trumf**. Amerikaner = laget
> (budvinner + hemmelig makker) tar alle stikk *med trumf og makker*.
> Solo-amerikaner = alle stikk alene, **fortsatt med trumf** (valgfritt etterlyst
> kort, ingen makker). Byttekort er standard (12 kort/hånd, budvinner vraker 4),
> budvinner **åpner første stikk i trumf**, poeng er 2× budvinner / 1× makker,
> først til 100. Den gamle «alene uten trumf»-modellen er **feil** og gjelder
> ikke.

---

## 1. Utgangspunkt: hva vi skal slå

MesterAI (`AI/MesterAI.swift` + `MesterVerden.swift` + `MesterSolver.swift` +
`NevroNett.swift`) er allerede en sterk søkebot:

- Determinisert Monte Carlo med ærlige slutninger (renons, makkerplikt,
  ønskekort, byttehaug), bud-vektede verdener.
- Eksakt dobbeltdummy (alfa-beta + transposisjon + sekvensreduksjon) fra ~6
  stikk igjen, grådig utrulling før det. Verifisert mot brute-force.
- Simulert budgivning, trumf/makkerkort og vrak på forventet poengsum.
- Destillert nevralt nett (NevroHjerne) som medspiller/reserve.
- **Målt:** 7,96 poeng/runde og 83 % partiseier mot «Vanskelig». Som budgiver
  89 % kontrakter.

Vi bygger altså ikke en løser fra bunnen – den finnes. Vi **gjenbruker**
`Dobbeltdummy`, `Spillinnsikt/sampleVerden` og `NevroNett`, og angriper der
MesterAI beviselig er svakest.

---

## 2. MesterAIs reelle svakheter (angrepsflaten)

| # | Svakhet | Hvorfor det koster poeng |
|---|---------|--------------------------|
| S1 | **Ingen spillhistorikk-vekting.** `sampleVerden` vekter kun mot kortantall + renons (+ bud). Den bruker ikke *hvordan* setene faktisk har spilt. | Verdener som motsier motstandernes/makkerens trekk får like stor vekt som de sannsynlige → dårligere slutning, feilspill. |
| S2 | **Grådig utrulling for tidlige stikk.** Åpningen spilles av en heuristikk, ikke søk. | Der usikkerheten (og gevinsten) er størst, er spillet svakest. |
| S3 | **Fast eksakt-grense (~6) + ~0,45 s/trekk, ingen pondering.** | Regnekraften mellom trekkene (mens andre spiller) kastes bort; eksakt sannhet kommer sent. |
| S4 | **Ren PIMC** (ingen ISMCTS). | «Strategy fusion»: søket later som det vil kjenne skjulte kort i framtida. |
| S5 | **Nettet er kun destillert** (imitasjon); AlphaZero-loopen er ikke lukket. | Nettet (~4,8/runde) ligger under søket – potensialet i søk-styrt trening er ubrukt. |

Crossover-måling (egen benchmark) som begrunner S3: eksakt dobbeltdummy koster
&lt; 1 ms opp til 6 kort/hånd, ~9 ms median ved 8, ~50 ms ved 9. Å heve
eksakt-grensen fra 6 til 8 er altså nesten gratis når den ligger på en
bakgrunnstråd.

---

## 3. Angrepet (prioritert etter forventet gevinst per innsats)

Hvert punkt måles direkte mot MesterAI som sparringspartner (§4).

### A. Spillhistorikk-vekting (importance sampling) — størst enkeltgevinst
Vekt hver samplet verden med **P(de faktisk spilte kortene | verden)**. Bruk
`NevroNett`s spillhode som motstandsmodell med en **støyparameter per
spillertype** (lav for President, høyere for svakere/mennesker). Utvider
MesterAIs eksisterende `budVekt` fra budhistorikk til *spillhistorikk*. Slår S1
og demper S4 samtidig, fordi usannsynlige verdener nedvektes i stedet for å
telle likt.

### B. Pondering + anytime-søk (utnytt motstandernes tid)
Start søket **i det hånden er kjent** og la det gå på en bakgrunnstråd mens de
tre andre spiller. Behold en løpende beste-trekk-anbefaling (anytime), les den
av når det blir vår tur → **0 ms opplevd forsinkelse** selv med sekunder med
regning. Ponder-hit: når en motstander spiller kortet søket ventet, gjenbrukes
deltreet; transposisjonstabellen holdes varm. Hev `eksaktStikkGrense` 6 → 8–9 og
øk antall verdener innenfor det samme myke tidsbudsjettet. Slår S3 og S2.

### C. ISMCTS i stedet for ren determinisert MC
Bytt aggregeringen fra «snitt over uavhengige verdener» til **Information Set
MCTS**: ett søketre over informasjonsmengder, determiniseringer trekkes per
utrulling. Demper S4 (strategy fusion) og gir naturlig anytime-oppførsel som
passer B.

### D. Konvensjonslag for likeverdige kort
Når simuleringen sier to kort er likeverdige (etter sekvensreduksjon / avkast),
velg etter en **dokumentert signal-konvensjon** (høyt = styrke, lavt = svakhet).
Koster aldri stikk, men gir makkeren – bot eller menneske – ekstra informasjon,
og boten leser samme konvensjon via vektingen i A.

### E. Nett-prior i søket (AlphaZero-steget)
La spillhodets fordeling **ordne og beskjære** kandidatkort i `velgKort`, og bruk
søkets besøksfordeling som nye treningsmål for nettet. Lukker loopen som gjorde
AlphaZero sterk, tilpasset determinisert MC + eksakt løser. Slår S5.

---

## 4. Målestokk (beviset)

- **Duplikat-scoring mot MesterAI:** samme kortstokker (seedet) spilles av begge
  boter i byttede seter; differansen i poeng/runde isolerer dyktighet fra
  kortflaks. MesterAI er baren – ikke heuristikken.
- **Suksesskriterium:** poeng/runde (Utfordrer − MesterAI) med 95 % CI helt over
  0 over ≥ 20 000 runder, og partiseier ≥ 55 % i direkte dueller.
- **CI-regresjonsvakt:** rask seedet test (Utfordrer ≥ MesterAI) i den
  eksisterende Linux-CI-en, så en endring aldri gjør boten svakere enn dagens.
- **Ærlig sluttport:** som NevroHjerne-treningen – gevinster i selvspill teller
  ikke før de består møtet med ferske runder mot flere motstandertyper.

Alt drives av `SeededGenerator` (reproduserbart), og CLI-en + Linux-CI-en
(«Kjernen uten Mac») kjører matchene uten Mac.

---

## 5. Gjenbruk vs. nytt

| Finnes (gjenbrukes) | Nytt som lages |
|---------------------|----------------|
| `Dobbeltdummy` eksakt løser | Spillhistorikk-vekting (A) i `sampleVerden`-aggregeringen |
| `Spillinnsikt` + `sampleVerden` (slutninger) | Ponder-tråd + anytime-styring (B) |
| `NevroNett` (policy/verdi) | ISMCTS-kjerne (C) som alternativ til snitt-over-verdener |
| `MesterKonfig` (tidsbudsjett, grenser) | Konvensjonslag (D) og nett-prior-loop (E) |
| CLI + Linux-CI + duplikat-harness | Regresjonsvakt: Utfordrer ≥ MesterAI |

---

## 6. Rekkefølge

1. **Målestokk først:** duplikat-harness Utfordrer-vs-MesterAI + baseline
   (MesterAI mot seg selv) → vi kan måle enhver endring.
2. **A – spillhistorikk-vekting** (størst gevinst, gjenbruker nett + sampler).
3. **B – pondering + hevet eksakt-grense** (lav risiko, ren ytelse).
4. **C – ISMCTS** (strukturendring; behold A/B som fallback og sammenlikning).
5. **D – konvensjonslag** (marginal, men gratis; hjelper også menneske-makker).
6. **E – nett-prior/AlphaZero-loop** (lengst horisont, størst tak).

Hver fase er ferdig først når duplikat-målingen mot MesterAI viser signifikant
framgang – ikke før.

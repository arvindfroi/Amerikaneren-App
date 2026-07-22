# Washington – måleresultater

Alle tall er duplikat-scoring: samme seedede kortstokker spilles av test- og
baselinekonfig i samme sete, differansen i poeng/runde isolerer effekten.
Motoren og løseren er uavhengig verifisert (fuzz 20 000 runder / 0 feil;
dobbeltdummy 920/920 mot brute-force).

| Eksperiment | Effekt (poeng/runde) | n | Konklusjon |
|-------------|----------------------|---|-----------|
| PIMC-kortspill (eksaktFra 5) vs grådig | +0,12 ± 0,17 | 2400 | ikke signifikant – PIMC bruker grådig i utrulling, skiller bare i eksakt sluttspill |
| **Simulert budgivning vs heuristisk bud** | **+1,07 ± 0,42** | 2000 | ✅ signifikant – største enkeltkilde til poeng |
| Angrep A: spillhistorikk-vekting vs uniform | +0,03 ± 0,16 | 1600 | ❌ **blindvei med grov motstandsmodell** (grådig-softmaks); trenger nevralt nett som modell |
| Angrep B: dypere eksakt (eksaktFra 7) | −0,08 ± 0,25 | 400 | ❌ ingen gevinst, og ~5 s/runde (for tregt) |
| Angrep C: ISMCTS (kontrakt-bevisst) vs PIMC | −0,50 ± 0,77 | 240 | ❌ slår ikke PIMC (bridge/spades-lever, men PIMC er sterk her) |

Absolutt (simulert bud + PIMC-spill mot heuristisk bord): ~6,5 poeng/runde.

## Lærdom (empirisk konklusjon)
1. **Budgivningen bærer gevinsten** – +1,07 p/runde. Fri simulert budgivning er
   Washingtons klart viktigste komponent.
2. **Kortspillet er nesten mettet av den grådige heuristikken.** Alle tre
   kortspill-tiltakene (PIMC, vekting, dypere eksakt) lander på ~0.
3. **Flaskehalsen er slutning, ikke regnekraft.** Å regne hardere (dypere eksakt)
   eller vekte *uniformt* samplede verdener hjelper ikke – man løser optimalt for
   feil verden. Kanten på kortspillet må komme fra en **ekte motstandsmodell**
   (nett), ikke mer søk. «Ren matematikk» gir bevist null på kortspillet.

## Veivalg videre
- **(a) Port budgivningen til Swift** og gjenbruk `NevroNett` som motstandsmodell
  for slutning/vekting – den vinnende komponenten inn i den ekte appen.
- **(b) Tren et lite policynett i C++** for vekting, og hold hele sløyfen lokal.

Dypere eksakt og heuristisk vekting er **empirisk utelukket** – ikke mer tid der.

## Om ISMCTS (bridge/spades-leveren)
ISMCTS (Cowling et al.) er den anerkjente fiksen for PIMCs strategy fusion, og
den naturlige neste kandidaten. Men den slår ikke PIMC her (−0,50). Det er
konsistent med forskning (Long, Sturtevant et al. 2010, «Understanding the
Success of PIMC»): i stikkspill med kort horisont og høy «disambiguation» er
PIMC uvanlig sterk, og ISMCTS gir ofte lite eller negativt. MesterAI ligger
altså nær taket for denne spillklassen.

## Bekreftelse: er MesterAI near-optimal?
Ny `optimalitet`-kommando i Swift-harnessen måler dobbeltdummy-gapet: for hvert
kortvalg (≤8 kort igjen) sammenlignes MesterAIs kort med det perfekt-informasjons-
optimale.

- **Kortspill (sluttspill, 1920 beslutninger over 60 runder): 97,4 %
  dobbeltdummy-optimale, snittfeil 0,028 stikk/beslutning.** Near-perfekt.

Dette forklarer direkte hvorfor ingen kortspill-lever bet på – marginen finnes
nesten ikke. Forbehold: måler sluttspillet (8 av 12 stikk); åpningen (12–9 kort,
der grådig utrulling brukes) er ikke målt og kan ha mer margin. Dobbeltdummy er
en øvre grense (perfekt info); full garanti krever utnyttbarhet (best-response).

## Ærlig delkonklusjon
Etter å ha målt bud (paritet – MesterAI har det alt), dypere eksakt (0), grov
vekting (0) og ISMCTS (−0,5): **ingen prøvd lever slår MesterAI.** Den er en
velbygd, nær-optimal PIMC+nett-bot. Gjenstående realistiske håp, i synkende
sannsynlighet: (1) nett-*guidet* søk (AlphaZero-stil prior/verdi – stor jobb,
krever nettet), (2) mer ISMCTS-tuning, (3) konvensjonssignaler. Ingen er
garantert.

## Referanse
MesterAI: 7,96 p/runde mot Vanskelig. Head-to-head når idéene er portert til
Swift er den endelige testen.

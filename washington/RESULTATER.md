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

## Referanse
MesterAI: 7,96 p/runde mot Vanskelig. Head-to-head når idéene er portert til
Swift er den endelige testen.

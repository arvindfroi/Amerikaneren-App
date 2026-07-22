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
| Angrep B: dypere eksakt (eksaktFra 7–8) | *måles* | – | – |

Absolutt (simulert bud + PIMC-spill mot heuristisk bord): ~6,5 poeng/runde.

## Lærdom så langt
1. **Budgivningen bærer gevinsten** – +1,07 p/runde. Fri simulert budgivning er
   Washingtons klart viktigste komponent.
2. **Vekting (A) krever en ekte motstandsmodell.** En heuristisk grådig-softmaks
   gir ~0. MesterAIs roadmap bruker nettet nettopp derfor – vekting utsettes til
   nettet er tilgjengelig (Swift-port) eller et lettvekts-policynett trenes i C++.
3. **Neste kortspill-kant er dypere eksakt (B), ikke vekting.**

## Referanse
MesterAI: 7,96 p/runde mot Vanskelig. Head-to-head når idéene er portert til
Swift er den endelige testen.

# Washington – måleresultater

Alle tall er duplikat-scoring: samme seedede kortstokker spilles av test- og
baselinekonfig i samme sete, differansen i poeng/runde isolerer effekten.
Motoren og løseren er uavhengig verifisert (fuzz 20 000 runder / 0 feil;
dobbeltdummy 920/920 mot brute-force).

| Eksperiment | Effekt (poeng/runde) | n | Merknad |
|-------------|----------------------|---|---------|
| PIMC-kortspill vs grådig heuristikk | +0,05 – +0,34 | 400–800 | liten; PIMC bruker grådig i utrulling, skiller bare i eksakt sluttspill |
| **Simulert budgivning vs heuristisk bud** | **+1,07 ± 0,42** | 2000 | signifikant; budgivning er største enkeltkilde til poeng |

Absolutt (simulert bud + PIMC-spill mot heuristisk bord): **6,54 poeng/runde**.

## Neste målinger (angrepet)
- A: spillhistorikk-vekting (WEIGHTED vs UNIFORM kortspill).
- B: dypere eksakt-grense / pondering (eksaktFra 4 → 7–8).
- Head-to-head mot MesterAI når idéene er portert til Swift (MesterAI: 7,96
  p/runde mot Vanskelig – vår referanse å passere).

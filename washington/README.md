# Washington — C++-forskningsmotor

**Opphav:** branch `plan-slaa-masterai-wmx70v`
**Kjerneidé:** Et frittstående C++-verktøy for å måle hva som faktisk kan slå
MesterAI: en verifisert spillmotor, en eksakt dobbeltdummy-løser, en PIMC-spiller,
en ISMCTS-prototype og fri simulert budgivning. Bygges uavhengig av Swift-appen.

## Innhold
- `game.hpp` — spillmotor · `solver.hpp` — dobbeltdummy-løser · `player.hpp` — PIMC
- `ismcts.hpp` — ISMCTS-prototype
- `harness.cpp` · `optimalitet.cpp` · `fuzz.cpp` · `solver_test.cpp`
- `RESULTATER.md` — fullstendige måletall

## Hovedfunn
Motoren og løseren er uavhengig verifisert (fuzz 20 000 runder / 0 feil;
dobbeltdummy 920/920 mot brute-force). Alle tall er duplikat-scoring.

| Eksperiment | Effekt (p/runde) | n | Konklusjon |
|-------------|------------------|---|-----------|
| **Simulert budgivning** vs heuristisk | **+1,07 ± 0,42** | 2000 | ✅ største enkeltkilde |
| PIMC-kortspill vs grådig | +0,12 ± 0,17 | 2400 | ikke signifikant |
| Angrep A: historikk-vekting | +0,03 ± 0,16 | 1600 | ❌ blindvei uten nevralt nett |
| Angrep B: dypere eksakt | −0,08 ± 0,25 | 400 | ❌ ingen gevinst, for tregt |
| Angrep C: ISMCTS vs PIMC | −0,50 ± 0,77 | 240 | ❌ slår ikke PIMC |

**Lærdom:** budgivningen bærer gevinsten; kortspillet er nesten mettet av den
grådige heuristikken; flaskehalsen er slutning, ikke regnekraft. Veivalg videre:
port budgivningen til Swift og bruk `NevroNett` som motstandsmodell.

Se `RESULTATER.md` for detaljene og `docs/PROSJEKT-WASHINGTON.md` i rota.

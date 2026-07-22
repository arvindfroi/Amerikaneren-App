# Lincoln — SO-ISMCTS

**Opphav:** branch `ismcts`
**Kjerneidé:** Single-Observer Information Set MCTS som alternativ til PIMC. Ett
tre bygges over informasjonssett; hver iterasjon sampler én lekkasjefri verden
(`Spillinnsikt.sampleVerden`) og utvider bare kort som er lovlige i den verdenen.

## Innhold
- `AI/` — komplett øyeblikksbilde av `Amerikaneren/AI/` med `MesterISMCTS.swift`
  (523 linjer, frittstående bot) + kroker i `MesterAI`/`MesterVerden`/`MesterSolver`.
- `extra/Tools/ismcts/` — måleverktøy (`sanitet`, `fart`, `h2h`, `kurve`,
  `skalering`, `tre`, `blad`) + `analyse.py`.
- `extra/docs/ismcts-maaling-2026-07-22.md` + `extra/docs/ismcts-raadata/` — rådata.
- `extra/Tests/MesterISMCTSTests.swift`.

## Målt resultat
Slår ikke PIMC her. Motivasjonen (strategifusjon) viste seg **teoretisk, ikke
empirisk** — fusjonstesten fant kurven over `eksaktStikkGrense` flat. Konsistent
med Washington (ISMCTS −0,50 mot PIMC) og med litteraturen (Long/Sturtevant
2010): i stikkspill med kort horisont er PIMC uvanlig sterk. Kjøringen ble
avsluttet før hele måleplanen var ferdig.

Se `Modeller/PRESIDENTER.md` for aktivering.

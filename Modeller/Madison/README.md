# Madison — budkalibrering

**Opphav:** branch `budkalibrering`
**Kjerneidé:** En justerbar budterskel og verktøyet for å finstille den. Siden
auksjonen er stigende og koden bare vurderer `minsteBud`, ER terskelen hele
budbeslutningen — og budgivningen er (jf. Washington) den største enkeltkilden
til poeng.

## Innhold
- `AI/` — komplett øyeblikksbilde av `Amerikaneren/AI/` med `MesterVekter.swift`
  (ny) + `budAggresjon`/`budkrok`/`overstyrFroe` i `MesterAI`/`AIPlayer`.
- `extra/Tools/harness/.../Budkalibrering.swift` — måleharness (`budkal`, `budab`).
- `extra/CLI/Evolusjon.swift` — turneringsevolusjon over heuristikkvektene.
- `extra/Tests/` — `MesterVekterTests`, `MesterAIJuksetest`, `Stikk2EVogABTests`.

## Byggeklosser
- `MesterKonfig.budAggresjon`: legges rett til tallbudets forventede poengsum i
  `velgBud`. 0 = dagens kalibrering, positivt = lettere å gå inn i budrunden.
- `MesterAI.budkrok`: gir måleverktøyet p-en, EV-en og stikkfordelingen MesterAI
  selv regnet ut ved hver budbeslutning (`nil` i vanlig spill).
- `MesterAI.overstyrFroe`: fast frø (portert fra `parallell-mester`).

## Status
Verktøyet for å kalibrere den komponenten som beviselig bærer gevinsten.
Naturlig neste steg sammen med Washingtons plan om å porte budgivningen til Swift.

Se `Modeller/PRESIDENTER.md` for aktivering.

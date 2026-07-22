# Jefferson — utbyttbar utrullingspolicy

**Opphav:** branch `utrullingspolicy` (inneholder også `parallell-mester`)
**Kjerneidé:** Utrullingen inne i hver samplede verden var låst til
`GraadigSpiller`. Her velges den med `MesterKonfig.utrullingspolicy`, og policyen
gjelder alle fire seter. I tillegg er verdensevalueringen parallellisert.

## Innhold
- `AI/` — komplett øyeblikksbilde av `Amerikaneren/AI/` med den omskrevne søke-
  løkka i `MesterAI.swift` (+434 linjer) og `MesterSolver.swift`.
- `extra/Tools/harness/.../Utrulling.swift`, `Parallell.swift` — måleharness.
- `extra/Tests/MesterParallellTests.swift`.

## Policyer
`graadig` (standard), `tilfeldig` (uniformt lovlig), `halvgraadig(p)`, `billig`
(følg farge, ta stikket billigst — uten utspills-/trumftrekkingsheuristikk).

## Målt resultat
Søket er **ufølsomt for utrullingens styrke**: ingen av fem alternative policyer
skiller seg fra grådig med 2 SE, i noen bredde. Uniformt tilfeldig ≈ grådig
(−0,04 ± 0,44 ved 36 verdener), selv om policybyttet endrer rundeutfallet i
34–40 % av rundene. Søket er derimot **sårbart for asymmetri** — som forklarer
hvorfor tidligere lokale forbedringer av utspillspolicyen svekket MesterAI.
Standarden beholdes på `.graadig`; aksen regnes som lukket.
**Parallelliseringen** er derimot en ren nytte.

Se `Modeller/PRESIDENTER.md` for aktivering.

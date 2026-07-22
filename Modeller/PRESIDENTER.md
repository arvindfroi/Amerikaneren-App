# Presidentene – konkurrerende AI-modeller

Dette er registeret over de konkurrerende «President-nivå»-botene for
Amerikaneren. Hver av dem var en egen utviklingsbranch; her er de samlet i
`main` som **separate, bevarte løsninger** slik at de kan sammenlignes og én
kan velges senere – uten at noe går tapt.

## Hvorfor de ligger utenfor bygget

Standardbygget (`Package.swift`) kompilerer **alle** `.swift`-filene under
`Amerikaneren/AI/` inn i én modul. To konkurrerende varianter av søkeboten kan
derfor ikke ligge der samtidig uten symbolkollisjon. Løsningen: den regjerende
boten (`MesterAI`) blir stående i `Amerikaneren/AI/` og er standard, mens hver
utfordrer bevares som et komplett, internt konsistent øyeblikksbilde under
`Modeller/<President>/` (ikke i `sources:` → bygges ikke → `main` forblir
grønn). Washington er et frittstående C++-tre og ligger på toppnivå i
`washington/`.

> ⚠️ **Ikke kompilert her.** Miljøet som konsoliderte disse hadde ingen
> Swift-toolchain. Kjør `swift build && swift test` lokalt før en modell tas i
> bruk. Kildebranchene er beholdt som backup til bygget er bekreftet.

## Slik aktiverer du en modell

Hver modell er et selvstendig øyeblikksbilde av `Amerikaneren/AI/`. For å prøve
en utfordrer:

```sh
# ta backup av den regjerende, bytt inn utfordreren, bygg
mv Amerikaneren/AI Amerikaneren/AI.mester
cp -r Modeller/Lincoln/AI Amerikaneren/AI
swift build && swift test
# tilbake:
rm -rf Amerikaneren/AI && mv Amerikaneren/AI.mester Amerikaneren/AI
```

Ekstra verktøy, tester og rådata for hver modell ligger under
`Modeller/<President>/extra/` (med original sti bevart).

## Registeret

| President | Opphavsbranch | Kjerneidé | Målt resultat | Status |
|-----------|---------------|-----------|---------------|--------|
| **MesterAI** (regjerende) | `main` | Søkebot: eksakt dobbeltdummy i sluttspill + samplet PIMC ellers, poengbasert målfunksjon, retrent NevroHjerne | Standarden alle måles mot | **Aktiv** i bygget |
| **Washington** | `plan-slaa-masterai-wmx70v` | Frittstående C++-motor: verifisert dobbeltdummy-løser, PIMC-spiller, ISMCTS-prototype, fri simulert budgivning | **Budgivning +1,07 p/runde** (største enkeltkilde). Kortspill mettet av grådig heuristikk (PIMC/ISMCTS/dypere ≈ 0) | Forskningsspor, C++ i `washington/` |
| **Lincoln** | `ismcts` | SO-ISMCTS: ett tre over informasjonssett som alternativ til PIMC | Slår ikke PIMC her (jf. Washington −0,50). Motivasjonen viste seg teoretisk, ikke empirisk | Utforsket, ikke adoptert |
| **Jefferson** | `utrullingspolicy` | Utbyttbar utrullingspolicy i søket + parallellisert verdensevaluering | Søket er **ufølsomt for utrullingens styrke** (uniform ≈ grådig, −0,04 ± 0,44). Aksen lukket | Målt negativt, parallellisering nyttig |
| **Madison** | `budkalibrering` | Justerbar budterskel (`budAggresjon`) + `MesterVekter` + budkrok for måling | Budgivningen ER hele beslutningen (stigende auksjon). Verktøyet for å finstille den vinnende komponenten | Verktøy for budkalibrering |

## Den store lærdommen (på tvers av modellene)

Alle sporene peker på det samme, mest tydelig fra Washington:

1. **Budgivningen bærer gevinsten** (+1,07 p/runde). Fri simulert budgivning er
   den klart viktigste komponenten. **Madison** er verktøyet for å finstille
   den; **Washington**s neste steg er å porte den til Swift.
2. **Kortspillet er nesten mettet** av den grådige heuristikken. Tre uavhengige
   spor (**Washington** PIMC/dypere, **Lincoln** ISMCTS, **Jefferson**
   utrullingspolicy) lander alle på ~0. Mer søk hjelper ikke.
3. **Flaskehalsen er slutning, ikke regnekraft.** Kanten på kortspillet må komme
   fra en ekte motstandsmodell (nevralt nett), ikke fra tyngre søk.

## Diagnose- og måleverktøy (merget inn i `main`)

Disse ble adoptert direkte i `main` fordi de ikke konkurrerer med søkeboten:

- **Regelfiks** (`card-game-trick-rules-bug`): budgiveren «visste» hvem makkeren
  var før makkerkortet ble lagt – rettet.
- **Web-GUI** (`web-gui`): spill mot MesterAI i nettleseren (`swift run
  Amerikaneren web`), trener-modus, pondering, tidsreise.
- **OpenSpiel-eksport** (`openspiel-eksport`): `eksporter-runder`-kommandoen.
- **Diagnose** (`fusjonstest`/`lekkasjediagnose`): kartlegging av hvor MesterAI
  selv taper poeng – se `docs/lekkasjekartlegging-2026-07-22.txt`. Fusjonstesten
  konkluderte at `eksaktStikkGrense`-kurven er flat (ingen endring adoptert).
- **Juksetest** (`mesterai-juksetest`): bevis for at MesterAI ikke bruker skjult
  informasjon.

## Overflødige brancher (helt dekket av andre)

- `parallell-mester` → inneholdt i **Jefferson** (`utrullingspolicy`).
- `lekkasjediagnose` → inneholdt i `fusjonstest` (merget til `main`).
- `card-game-trick-rules-bug` → merget til `main`.

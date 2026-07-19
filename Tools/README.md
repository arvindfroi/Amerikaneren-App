# Verktøy: trening og benchmarking

To SwiftPM-pakker som kjører på Mac eller Linux (Swift 5.9+). Begge
bruker **symlenker** inn i `Amerikaneren/` – de kompilerer alltid mot
nøyaktig samme motor- og AI-kode som appen, uten kopier som kan
divergere.

```sh
cd Tools/trainer && swift build -c release   # treningsharness
cd Tools/harness && swift build -c release   # benchmark/fuzz-harness
```

## trainer – treningsharnessen for NevroHjerne

```
gen <fil> <frøStart> <matcher>    destilleringsdata fra MesterAI-selvspill
train <datafiler...>              veiledet trening → vekter.bin
rl <matcher> <lr>                 REINFORCE-selvspill (partiseier = belønning)
eval [runder] [matcher]           nett-argmax mot 3× Vanskelig-heuristikk
export <ut.swift>                 vekter.bin → Amerikaneren/AI/NevroVekter.swift
importer <inn.ndjson> <ut.bin> [mennesker|alle]
                                  innsamlede partiopptak → treningsdatasett
syntetisk <ut.ndjson> <frø> <n>   lag NDJSON-testdata i samme format som appen
```

Typisk løp for å trene videre på innsamlede partier (se `docs/DATA.md`):

```sh
# 1. Hent data fra backenden (NDJSON)
curl -H "X-Admin-Nokkel: $ADMIN_NOKKEL" "https://<backend>/v1/eksport" > partier.ndjson
# 2. Avspill + verifiser + høst beslutninger (mennesker og President-CPU-er)
./.build/release/trainer importer partier.ndjson menneskedata.bin
# 3. Tren med både lærerdata og menneskedata, evaluer, eksporter
./.build/release/trainer train lærerdata-*.bin menneskedata.bin
./.build/release/trainer eval 2000
./.build/release/trainer export ../../Amerikaneren/AI/NevroVekter.swift
```

`importer` spiller av hvert parti gjennom den ekte motoren og forkaster
alt som ikke er hundre prosent regelriktig – ett ugyldig trekk og hele
partiet vrakes. Treningen kan aldri forgiftes av korrupte eller tuklede
opptak.

Fargesymmetri-augmentering er innebygd i `train` (sett `UTEN_AUG=1` for
bit-eksakt reproduksjon). `eval`-porten måler alltid på ferske,
tilfeldige runder mot andre motstandertyper enn treningen – gevinster
som ikke overlever ekte spill blir aldri eksportert.

## harness – benchmark og fuzz

```
dd            dobbeltdummy-løser mot brute-force-minimax
tid           tidsbudsjett/ytelse per trekk
fuzz          hele runder fuzz-testes for lovlighet
motorfuzz     egenskapsbasert regelverifisering med uavhengig fasit
styrke        poeng/runde mot 3× Vanskelig
parti         hele partier til 100 poeng
ab            A/B mellom to MesterKonfig-oppsett
format        fast rundetall vs. først-til-100
scenario      konstruerte sluttspill med kjent fasit
```

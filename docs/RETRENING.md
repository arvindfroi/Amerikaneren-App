# Retrening av NevroHjerne etter regelfiksen (v0.13)

Regelfiksen i v0.13 (budvinneren må åpne første stikk i trumf, se
`REGLER.md` og `UTVIKLINGSLOGG.md`) gjør at NevroHjerne-vektene er
trent under feil regler. MesterAI (søket) og heuristikk-AI-ene ble
riktige i samme øyeblikk som motoren – nettet brukes bare som
forslagsstiller/fallback, så appen spiller korrekt i dag. Men nettet
bør trenes om for at forslagene skal treffe igjen.

Planen under er laget for en maskin med mange kjerner (målt utgangspunkt:
~7 s per match per kjerne, ~590 spilleksempler og ~0,6 MB data per match).

**Nøkkelinnsikt:** treneren er én-trådet – én `gen`-prosess bruker én
kjerne. Parallelliteten hentes ved å kjøre mange `gen`-shards samtidig
med ulike frø; `train` tar imot flere datafiler.

## Fase 0 – Oppsett og sanity (5 min)

```sh
cd Tools/trainer && swift build -c release
cd ../harness && swift build -c release
./.build/release/harness dd && ./.build/release/harness motorfuzz 2000
```

Krever Swift 6 (nativt eller `swift:6.0-noble`, samme som devcontaineren).
Harness-kjøringen bekrefter at regelfiksen står seg lokalt før man
bruker timer på datagenerering.

## Fase 1 – Generer lærerdata i parallell (~20–60 min på 24 kjerner)

```sh
cd Tools/trainer
N=20    # shards; la noen kjerner stå igjen
M=250   # matcher per shard → 5 000 totalt
for i in $(seq 1 $N); do
  ./.build/release/trainer gen lærerdata-$i.bin $((i*100000)) $M &
done
wait
```

- **Ulike frø-startpunkter per shard** (som over) – ellers genereres
  identiske matcher.
- 5 000 matcher ≈ 3 GB data / ~3 mill. spilleksempler – godt startpunkt.
  `train` laster alt i RAM, så ikke gå over ~10 000 matcher (~6 GB)
  uten 32+ GB minne.
- Kjør gjerne 20×50 først for å verifisere hele løypa ende-til-ende,
  og skaler så opp.

## Fase 2 – (Valgfritt) importer menneskedata

```sh
curl -H "X-Admin-Nokkel: $ADMIN_NOKKEL" "https://<backend>/v1/eksport" > partier.ndjson
./.build/release/trainer importer partier.ndjson menneskedata.bin
```

Forvent høy avvisning: importen er alt-eller-ingenting **per parti** –
ett eneste stikk der budvinneren åpnet utenom trumf vraker hele partiet.
Overlever lite, er det greit å kjøre på ren lærerdata denne runden.

## Fase 3 – Tren (én-trådet, la den stå)

```sh
./.build/release/trainer train lærerdata-*.bin   # + menneskedata.bin hvis den ga noe
```

Følg med på `testtreff`/`vraktreff` per epoke – de skal stige og flate
ut. Resultatet blir `vekter.bin`.

## Fase 4 – Eval-port før eksport

```sh
./.build/release/trainer eval 2000
```

Måler nettets argmax mot 3× Vanskelig-heuristikken på ferske runder
(andre motstandere enn treningen – gevinster som ikke tåler ekte spill
stoppes her). Krav for å gå videre: klart positiv poeng/runde.

## Fase 5 – (Valgfritt) RL-selvspill

```sh
./.build/release/trainer rl 3000 3e-5 vekter.bin
```

REINFORCE med deterministisk fremdriftsmåling mot frosset startnett –
eksporterer bare forbedringer. Dette er steget som kan løfte nettet
forbi læreren, men det er tidkrevende og kan tas i en senere økt.

## Fase 6 – Eksporter, verifiser, commit

```sh
./.build/release/trainer export ../../Amerikaneren/AI/NevroVekter.swift
cd ../.. && swift test
cd Tools/harness && ./.build/release/harness fuzz && ./.build/release/harness styrke 150
```

`styrke` er sluttkontrollen: President-nivået (som bruker nettets
forslag inne i søket) skal være likt eller bedre enn før. Commit av
`NevroVekter.swift` er hele leveransen – vektene er innebygd i appen.

## Fallgruver

- Ikke sett `UTEN_AUG=1` – det skrur av fargesymmetri-augmenteringen og
  finnes bare for bit-eksakt reproduksjon.
- Ta vare på `lærerdata-*.bin`-shardene til du er fornøyd – da kan du
  re-trene med andre hyperparametre uten å regenerere.

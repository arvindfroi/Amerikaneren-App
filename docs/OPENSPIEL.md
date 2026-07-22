# OpenSpiel-porten og GPU-treningen

Amerikaneren er portert til [OpenSpiel](https://github.com/google-deepmind/open_spiel)
slik at moderne selvspill-algoritmer for spill med skjult informasjon kan
trenes på GPU – uten å røre Swift-motoren, som forblir regelfasit.

## Hvorfor

Turneringsevolusjonen over `MesterVekter` (se `docs/AI.md`) viste at
vektlandskapet rundt de håndsatte konstantene er flatt: 34 generasjoner, 7
ankermålinger og en bekreftelsesmåling på n=1500 ga ingen gevinst. Formelen
selv er taket. Videre fremgang krever rikere strukturer – altså lærte
politikker – og de trenes best i et rammeverk bygget for formålet.

## Arkitektur

```
Swift-motoren (GameEngine)        ← regelfasit, aldri kopiert
   │
   ├── eksporter-runder ─────────→ paritetstest mot C++-porten
   │
   └── arena-bro ────────────────→ JSON-linjer over stdin/stdout
                                     ↑
C++-porten (open_spiel/games/amerikaneren)
   │                                 │
   └── pyspiel ──→ NFSP-trening (PyTorch/CUDA) ──┘
```

* **Paritet før alt.** C++-implementasjonen er verifisert mot Swift-motoren
  over 10 000 runder / 578 682 beslutningspunkter: settet av lovlige
  handlinger var identisk ved hvert punkt, og sluttpoengene stemte. Ett
  avvik stopper alt – regeldrift mellom to implementasjoner er den store
  faren ved en slik port.
* **Én episode = én runde.** Poengstillingen inn i runden er en
  spillparameter (`poeng0..3`), så matchkontekst kan trenes senere.
* **Arenaen er en løpende paritetstest.** Ved hvert eksternt beslutningspunkt
  kreves identiske lovlige handlinger, og til slutt identiske returns.

## Kommandoer

```sh
# Eksporter runder fra Swift-motoren (fasit for paritetstesten)
Amerikaneren eksporter-runder 5000 20260721 > paritet-runder.jsonl
python open_spiel/games/amerikaneren/paritetstest.py paritet-runder.jsonl

# Arena: NFSP-politikk mot MesterAI, parret blokkdesign
python open_spiel/games/amerikaneren/arena.py \
    --politikk nfsp --sjekkpunkt <sti>/siste.pt --graadig \
    --eksterne 0 --blokker 50 --tid 0.2 --merkelapp min-maaling
```

## Målte resultater (natt til 22. juli 2026)

Poeng per runde, parret blokkdesign, MesterAI-budsjett 0,05 s:

| Part | Ved ep 85 000 (avg-policy) | Ved ep 265 000 (grådig) |
|---|---|---|
| NFSP | −27,5 ± 1,5 | **+0,27 ± 0,57** |
| MesterAI | +3,6 ± 0,6 | +4,75 ± 0,59 |
| Random | −35,2 ± 1,6 | – |

Merk at MesterAI ved 0,05 s er kraftig nedskalert (maksVerdener 12); appen
kjører 0,45 s. Tallene er altså ikke et mål på appens MesterAI.

## Fallgruver som kostet tid (les før du gjentar dette)

1. **Epsilon-skjemaet telles i DQN-iterasjoner, ikke miljøsteg.** `DQN.step`
   kalles bare i best-response-modus (anticipatory ≈ 0,1) og bare på egne
   trekk (~1/4), så telleren er ~2,5 % av spillstegene. Nedtrapping satt i
   «steg» blir ~34× for treg. Logg `dqn_iter` så enheten er etterprøvbar.
2. **OpenSpiels `exponential_schedule` metter.** Den bruker
   `decay_steps = min(t, duration)`, så epsilon stopper på
   `end + (start − end)·e⁻¹ ≈ 0,41` og kommer aldri lavere.
3. **Gjennomsnittspolicyen trenes på utforskningsstøy.** SL-målet for et
   utforskende steg er den uniforme fordelingen over lovlige handlinger.
   I åpningsbudet er 10 av 11 lovlige handlinger bud, så avg-nettet lærer å
   by vilt selv når den grådige politikken passer fornuftig. Mål alltid
   begge politikkene hver for seg (`analyse-tmp/budinstrument.py`).
4. **Batch-1-inferens sulter GPU-en.** Miljøet i C++ gir ~105 000 steg/s,
   men treningsløkka gikk 1 900 med ett forward-pass per beslutning.
   Vektorisert utrulling (1024 parallelle spill, ett batchet pass per tick)
   ga 7 500 steg/s og GPU-utnyttelse 15 % → 87 %.
5. **Gamma skal være 1,0** i et spill der hele belønningen kommer til slutt,
   og belønningsskalaen (±24 med huber `beta = 5`) skal stå urørt –
   normalisering krymper effektiv læringsrate.

## Driftserfaringer

* **En selvhelbredende mekanisme uten hastighetsbrems er en
  selvforsterkende feil.** En vaktbikkje som sjekket feil prosessnavn
  erklærte en kjøring død hvert annet minutt og startet ni kopier før
  minnet tok slutt – som drepte all trening. Erstatteren identifiserer
  kjøringer på `--katalog` *eller* arbeidskatalog, dobbeltsjekker før
  oppstart, og har tre uavhengige bremser (startkvote per katalog, global
  prosessgrense, minnevakt).
* **Skriv resultater til varig fil fra prosessen selv.** `swift test | tail`
  bufrer til EOF og kaster alt annet; en flertimers måling gikk tapt slik.
* **WSL-VM-en kan restarte seg selv** (`Wsl/Service/E_UNEXPECTED`). Alt som
  skal overleve natten må kunne gjenopptas fra sjekkpunkt.

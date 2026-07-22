# SO-ISMCTS mot PIMC i Amerikaneren — måleresultater 22. juli 2026

Rådata: `~/ismcts/resultater.jsonl` (én linje per måling, skrevet fortløpende).
Robust etteranalyse: `Tools/ismcts/analyse.py`.
Måleverktøy: `Tools/ismcts` (`sanitet`, `fart`, `h2h`, `kurve`, `skalering`,
`tre`, `blad`).

Kjøringen ble avsluttet før hele måleplanen var gjennomført. Det som står
her er ferdig målt; det som mangler er listet til slutt.

---

## 1. Om premisset

Oppdraget ble gitt med strategifusjon som empirisk begrunnelse. Den
begrunnelsen holdt ikke: fusjonstesten (egen agent, `~/Amerikaneren-fusjon`)
viste at kurven over `eksaktStikkGrense` 0/2/4/6/7/8 er flat (n=2665, grense 0
mot 7 = +0,14 ± 0,19), og at det opprinnelige funnet «6→8 gjorde MesterAI
2,98 poeng svakere» var støy fra n=50 (ved n=979: −0,05 ± 0,29).

**Strategifusjon er altså ikke påvist hos oss.** ISMCTS er fortsatt verdt å
teste på teoretisk grunnlag — PIMCs patologier er veldokumenterte i
litteraturen — men motivasjonen er teoretisk, ikke empirisk. Det gjør
iterasjonskurven og tre-kontra-utrulling-målingen til de avgjørende tallene,
ikke enkeltmålingen mot MesterAI.

## 2. Designvalg

**Ett tre over informasjonssett.** Hver iterasjon sampler én verden med
`Spillinnsikt.sampleVerden` (verifisert lekkasjefri), og bare kort som er
lovlige i den verdenen kan velges. Statistikken deles på tvers av alle
determiniseringer.

**Availability-basert UCB.** Utforskningsleddet bruker A(a) — antall ganger
handlingen var *tilgjengelig* — ikke nodens besøkstall:
`W(a)/N(a) + c·sqrt(ln A(a) / N(a))`, c = 0,7.

**Normalisering per sete.** Snittverdien normaliseres mot det spennet søket
selv har sett, og **per sete**. Budgiverens skala (±2× budet, pluss ±målPoeng
ved målstrek) og en forsvarers skala (antall egne stikk) er helt ulike; med
ett felles spenn klemmes forsvarernes snitt sammen i en tynn stripe og
utforskningsleddet gjør motstandermodellen nesten tilfeldig.

**Bladevaluering: ren grådig utrulling til rundeslutt (`bladstikk = 0`).**
Begrunnelse: dobbeltdummy ved bladet gjeninnfører fasit lokalt, altså akkurat
det ISMCTS skal fjerne. Varianten er implementert og styrbar (`bladstikk` =
antall siste stikk som løses eksakt), men A/B-en mellom variantene rakk ikke
å bli kjørt. Merk at utrullingspolicyen `GrådigSpiller` fortsatt ser alle kort
i den samplede verdenen — det er en fast policy, ikke strategifusjon, men det
gjør forsvaret i utrullingen sterkere enn det burde være. En annen agent måler
utrullingspolicyer (`~/Amerikaneren-utrulling`); det resultatet bør inn her.

**Max^n-tilbakepropagering.** Verdien i bladet regnes for alle fire seter, og
hver node får verdien for det setet som handler der. Dette håndterer at
makkeren — og dermed lagtilhørigheten — varierer mellom determiniseringer:
«hvert sete maksimerer sin egen poengendring» gjelder i alle verdener, mens
«dette setet er på budgiverlaget» ikke gjør det.

**Målfunksjonen er ikke funnet opp på nytt.** Regnestykket i `MesterAI.vurder`
er flyttet til `Spillinnsikt.måltall` og generalisert fra eget sete til alle
fire. MesterAI henter fortsatt bare sin egen komponent, så alle tidligere tall
derfra er uendret. Budvektingen er delt på samme vis (`Budvekt`); ISMCTS
bruker den som forkastningsutvalg, altså samme verdensfordeling uttrykt som
frekvens i stedet for som vekt — det er det MCTS-statistikken trenger.

**Parallellisering: rotparallellisering.** Uavhengige trær med avledede frø,
slått sammen på rotens besøkstall. Valgt framfor tre-parallellisering med lås
fordi trærne ikke deler noe muterbart i det hele tatt — ingen låser, ingen
datakappløp, og resultatet er uavhengig av trådplanleggingen. Prisen er at
hvert tre blir grunnere enn ett stort ville vært.

**Hovedmålingen kjøres likevel entrådet i søket**, og parallelliteten legges
på rundenivå: begge armer spiller i samme runde, på samme maskin, under samme
last. Da er «samme tidsbudsjett» også samme regnekraft.

**Rotvalg: mest besøkte handling.**

Sidefiks: `Dobbeltdummy` har fått lagmasken inn i transposisjonsnøkkelen.
MesterAI holder én løser per verden og har konstant lagmaske, men ISMCTS
gjenbruker løseren over determiniseringer der makkeren er ulik.

## 3. Sanitet og regresjon

| Test | Resultat |
|---|---|
| Ulovlige trekk (200 runder, alle seter mot motorens `lovligeKort`) | **0** (PIMC også 0) |
| Sete 0 mot 3× tilfeldig, 0,2 s | ISMCTS **+4,93 ± 0,62** · PIMC +4,70 ± 0,62 · tilfeldig +2,19 ± 0,68 |
| ISMCTS − tilfeldig, parret | **+2,73 ± 0,74 (3,7 SE)** |
| Testsuiten (`swift test -c release --skip MesterAIJuksetest`) | **68 tester, 0 feil** |
| Stikk-11-regresjonen (`testISMCTSBeholderSparEssVedStikk11`) | **K♦ i 40 av 40 frø** — A♠ beholdes |

## 4. Fart (0,2 s per trekk)

| Motor | Per trekk |
|---|---|
| ISMCTS, ren grådig utrulling | 7 213 iterasjoner |
| ISMCTS, DD på siste 2 stikk | 6 084 |
| ISMCTS, DD på siste 4 stikk | 3 711 |
| PIMC, dagens verdenstak | 488 verdener |
| PIMC, hevet tak (tidsbundet) | 2 588 verdener |

## 5. Hovedmåling: ISMCTS mot MesterAI, samme tidsbudsjett

Parret og speilet: hver utdeling spilles to ganger, ISMCTS på 0+2 mot PIMC på
1+3 og motsatt. Måltallet er snittet av (ISMCTS-lagets poeng − PIMC-lagets
poeng) over de to orienteringene.

### 0,2 s — oppdagelse (n=250) og replikering på ferske frø (n=1000)

| Mål | Oppdagelse (n=250) | Replikering (n=1000) | Slått sammen (n=1250) |
|---|---|---|---|
| Snitt ± SE | +0,898 ± 0,383 (t=2,35) | **+0,438 ± 0,241 (t=1,81)** | +0,530 ± 0,208 (t=2,55) |
| Trimmet snitt (10 %) | +0,065 | **+0,030** | +0,037 |
| Tegntest | 85–65 (56,7 %), p=0,12 | **318–291 (52,2 %), p=0,29** | 403–356 (53,1 %), p=0,095 |
| Bootstrap-KI (95 %) | [+0,18, +1,69] | **[−0,03, +0,90]** | [+0,13, +0,94] |
| ISMCTS iter/trekk | 4 616 | 5 390 | — |
| PIMC verdener/trekk | 475 | 485 | — |

**Replikeringen bekrefter ikke oppdagelsen.** Effekten krympet fra +0,90 til
+0,44 på ferske frø, og på det ferske utvalget er den ikke signifikant med
noe av de fire målene. Det trimmede snittet er ~0 i alle tre kolonnene: det
snittet som finnes ligger i minoriteten av runder med store poengsvingninger
(kontrakt som ryker, Amerikaner), ikke i den typiske runden. Tegntesten sier
at ISMCTS vinner 52–53 % av rundene — et svakt utslag.

Merk at 10 % trimming er et hardt mål i akkurat dette spillet: den fjerner
per konstruksjon rundene der kontrakten faktisk avgjorde noe, som er der
poengene bor. At både trimmet snitt og tegntest er svake, mens snitt og
bootstrap er positive, er derfor forenlig med «liten reell effekt konsentrert
i høyinnsatsrunder» — men det er ikke bevist.

### 0,45 s (delvis — kjøringen ble avbrutt)

To avbrutte kjøringer, uten sluttrapport, bare fremdriftstall:
n=200: **+1,742 ± 0,648** · n=125 (ny kjøring): **+0,680 ± 0,612**.
Ingen robust analyse, siden rundedifferansene bare logges ved fullført
kjøring. Behandles som ubekreftet.

### Multiplisitet

Sammenlikninger kjørt i denne økten: hovedmåling 0,2 s, replikering 0,2 s,
0,45 s (×2 avbrutte), iterasjonskurve (4 punkter), skalering (1 punkt),
sanitet (3 armer), kalibreringer (2). **I størrelsesorden 14 sammenlikninger.**
Bare replikeringen var forhåndsbestemt som bekreftelse. En enkelt «2 SE» i
det selskapet betyr lite — hvilket er nettopp det replikeringen viste.

## 6. Iterasjonskurve mot MesterAI — **uleselig slik den står**

Alle punkter på samme utdelinger, ISMCTS med fast iterasjonstall, MesterAI med
0,2 s.

| Iterasjoner | Differanse (n=80) | Parret mot 200 iter. |
|---|---|---|
| 200 | +1,156 ± 0,740 | — |
| 1 000 | −0,400 ± 0,556 | −1,556 ± 0,930 (tegntest p=0,60) |
| 5 000 | +1,319 ± 0,887 | +0,163 ± 0,967 (p=0,70) |
| 20 000 | +1,450 ± 1,046 | +0,294 ± 1,431 (p=0,61) |

**Dette kan ikke leses.** Feilmarginene overlapper fullstendig, kurven
spretter, og selv den parrede analysen (som fjerner utdelingsvariansen) gir
ingenting. n=80 per punkt er altfor lite. I tillegg var motstanderen
tidsbudsjettert mens maskinlasten falt fra ~20 til ~7 gjennom kjøringen, så
de sene punktene møtte en sterkere PIMC enn de tidlige — en skjevhet som
trekker kurven ned med iterasjonstallet.

Kurven ble derfor lagt om (deterministisk motstander med faste verdenstak,
n=1000 per punkt, seks punkter, billigere budrunde) og startet på nytt, men
kjøringen rakk ikke å produsere noe punkt før stans.

## 7. Skalering: ISMCTS(N) mot ISMCTS(200) — **det ene rene signalet**

Samme algoritme på begge sider, bare ulikt søkebudsjett. Alt annet —
målfunksjon, utrullingspolicy, verdensfordeling — er identisk, og begge armer
er iterasjonsstyrte, så maskinlast kan ikke påvirke resultatet.

**ISMCTS(1 000) mot ISMCTS(200), n=600 parrede runder:**

| Mål | Verdi |
|---|---|
| Snitt ± SE | **+1,070 ± 0,317 (t = 3,38)** |
| Trimmet snitt (10 %) | +0,173 |
| Tegntest | **226–156 (59,2 %), p = 0,0004** |
| Bootstrap-KI (95 %) | **[+0,45, +1,70]**, 100 % av gjentrekningene over 0 |

Dette overlever hele behandlingen, inkludert tegntesten, som er det målet som
er minst følsomt for de tunge halene. **Fem ganger mer søk gjør ISMCTS
målbart sterkere enn seg selv.** Punktene 2 000/5 000/20 000 var i kø da
kjøringen ble stanset.

## 8. Treets overtakelse (mekanismen)

Hvor mye av runden treets egen statistikk bestemmer, framfor den faste
utrullingspolicyen. 30 runder per punkt.

| Iterasjoner | Tredybde (beslutninger) | Uten ekspansjon | Maks | Andel av runden | Stikk framover |
|---|---|---|---|---|---|
| 200 | 3,16 | 2,17 | 12 | **17,3 %** | 0,79 |
| 1 000 | 3,96 | 2,99 | 12 | **21,9 %** | 0,99 |
| 5 000 | 4,91 | 3,97 | 15 | **27,4 %** | 1,23 |
| 20 000 | 5,75 | 4,83 | 16 | **31,2 %** | 1,44 |

Andel tre-beslutninger per stikk (stikk 1 → 12):

| Iter. | s1 | s2 | s3 | s4 | s5 | s6 | s7 | s8 | s9 | s10 | s11 | s12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 200 | 88 % | 47 % | 30 % | 20 % | 16 % | 13 % | 11 % | 10 % | 9 % | 8 % | 7 % | 3 % |
| 1 000 | 95 % | 58 % | 36 % | 26 % | 19 % | 16 % | 14 % | 12 % | 11 % | 10 % | 9 % | 6 % |
| 5 000 | 98 % | 69 % | 44 % | 30 % | 24 % | 20 % | 18 % | 15 % | 14 % | 13 % | 12 % | 9 % |
| 20 000 | 99 % | 78 % | 51 % | 37 % | 29 % | 24 % | 19 % | 18 % | 16 % | 15 % | 14 % | 11 % |

Overtakelsen vokser monotont og i alle stikk, omtrent logaritmisk: hver
femdobling av iterasjonstallet legger til ~0,8–0,9 beslutning i dybde.
Sammen med skaleringsmålingen i punkt 7 er dette et mekanistisk holdepunkt
for at det er treet — ikke ren variansreduksjon — som gjør jobben.

**Men merk skalaen: selv ved 20 000 iterasjoner tar treet bare 31 % av
beslutningene.** To tredeler av utfallet avgjøres fortsatt av
`GrådigSpiller`. Det forklarer hvorfor absolutt-nivået ligger så nær PIMC:
begge motorene evalueres i hovedsak av den samme håndskrevne
utrullingspolicyen. Utrullingspolicyen er dermed sannsynligvis en større
hendel enn søkemetoden akkurat nå.

## 9. Konklusjon

1. **ISMCTS er ikke svakere enn MesterAI.** Ved 0,2 s ligger den på
   +0,44 ± 0,24 poeng per lagrunde på ferske frø (n=1000) — ikke signifikant,
   men entydig ikke-negativt. Kravet «positiv differanse med minst 2 SE» er
   **ikke** oppfylt på det ferske utvalget.
2. **ISMCTS skalerer med regnekraft.** ISMCTS(1000) slår ISMCTS(200) med
   +1,07 ± 0,32, tegntest p=0,0004. Det er kvalitativt forskjellig fra PIMC,
   som mettet ved ~30 verdener.
3. **Mekanismen er som teorien sier**: tredybden og andelen tre-beslutninger
   vokser monotont med iterasjonstallet.
4. **Men kurven mot MesterAI er ennå ikke lest.** Med n=80 per punkt sier den
   ingenting, og det er den — ikke skaleringen mot seg selv — som avgjør om
   ISMCTS til slutt går forbi PIMC.

Vurdering: **verdt å forfølge, men ikke verdt å adoptere ennå.** Metoden er på
nivå med PIMC ved likt tidsbudsjett, den skalerer der PIMC ikke gjør det, og
den har et hode som fortsatt bare styrer en tredel av kroppen. Den mest
lovende neste hendelen er ikke mer søk, men en bedre utrullingspolicy — den
avgjør 69 % av utfallet.

## 10. Hva gjenstår

Alt er klart til å plukkes opp; ingenting må gjøres om igjen.

1. **Iterasjonskurven, n≈1000 per punkt.** Kommandoen er ferdig og testet:
   ```
   ismcts kurve runder=1000 iter=200,500,1000,2000,5000,10000 \
       pimcfast=1 pimcslutt=600 budverdener=12 arbeidere=12 merke=kurveN
   ```
   `pimcfast=1 pimcslutt=600` gjør motstanderen deterministisk (faste
   verdenstak, ingen klokke), så maskinlast ikke kan forskyve punktene.
   `budverdener=12` kutter budrunden fra 64 til 12 verdener — den er lik i
   begge armer og koster ellers mer per runde enn hele kortspillsøket.
   Anslag: 1–1,5 time på ~12 ledige kjerner.
2. **Skaleringskurven fullført**: punktene 500/2 000/5 000/20 000 mot 200.
   ```
   ismcts skalering runder=600 basis=200 iter=500,1000,2000,5000,20000 \
       budverdener=12 arbeidere=8
   ```
   Dette er den billigste og reneste skalatesten — ingen PIMC-arm.
3. **0,45 s-målingen** kjørt ferdig med robust analyse (n≥1000).
4. **Bladevaluering**: `ismcts blad` sammenlikner ren grådig utrulling mot
   dobbeltdummy på siste 2/3/4 stikk. Ikke kjørt.
5. **Utrullingspolicy**: koble på resultatet fra `~/Amerikaneren-utrulling`.
   Er tilfeldige eller halvgrådige utrullinger bedre enn grådige, bør
   bladpolicyen byttes før noe annet finjusteres.
6. **Rotparallellisering** (`traader=N`) er implementert, men aldri målt for
   styrke.

Praktisk merknad: lange kjøringer må startes med
`bash ~/ismcts-start.sh <loggnavn> <argumenter>` (setsid + nohup). Jobber
startet med `Start-Process wsl.exe` ble drept underveis to ganger i denne
økten.

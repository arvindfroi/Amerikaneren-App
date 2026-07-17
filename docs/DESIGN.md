# Designsystem og UX-prinsipper

> **Status: UTKAST.** Retning for identitet, navigasjon og interaksjon er
> ikke besluttet ennå – se [BESLUTNINGER.md](BESLUTNINGER.md) for de åpne
> valgene. Tokens-arkitekturen under ligger fast; verdiene kan byttes
> billig når retningen velges.

Alle tokens ligger i `Theme/DesignSystem.swift` (`DS`). Eldre views bruker
`Theme`-fasaden, som peker på de samme tokens – nye views skal bruke `DS`
direkte.

## Identitet

**«Brain Training møter americana.»** Kremhvitt papir, mørkeblått blekk,
rød aksent og runde, håndtegnede former – som en vennlig arbeidsbok.
Amerikansk tematikk (stjerner, striper, presidentene) brukes som krydder i
innhold og karakterer, aldri som bakgrunnstapet.

## Farger (`DS.Farge`)

| Token | Hex | Bruk |
|-------|-----|------|
| `papir` | `F7F1E1` | Hovedbakgrunn |
| `papirMørk` | `EFE6CE` | Spillebordets bakgrunn |
| `flate` | hvit 80 % | Paneler og kortflater |
| `blekk` | `1D3557` | Primærtekst, spar/kløver |
| `blekkSvak` | blekk 55 % | Sekundærtekst |
| `linje` | blekk 14 % | Kantlinjer |
| `rød` | `E63946` | Primærhandling, hjerter/ruter, aksent |
| `blå` | `457B9D` | Sekundærhandling |
| `grønn` | `2A9D8F` | Suksess, «din tur», lovlige kort |
| `gul` | `E9C46A` | Fremheving, snakkebobler |
| `bordfilt` | grønn 12 % | Stikk-området på bordet |

Regel: **rød = handling, grønn = status/lov, blå = navigasjon/sekundært.**
Aldri farge alene som eneste signal (nedtonede kort er også ikke-trykkbare).

## Typografi (`DS.Tekst`)

Alle stiler er bygget på iOS-tekststiler med `rounded`-design, slik at
**Dynamic Type** («større tekst» i systeminnstillingene) skalerer hele
appen automatisk – en del av bestemor-testen.

| Stil | Basert på | Bruk |
|------|-----------|------|
| `display` | largeTitle black | App-tittel, seiersskjermer |
| `tittel` | title2 heavy | Skjermtitler |
| `overskrift` | headline bold | Paneloverskrifter |
| `brød` | body medium | Løpende tekst |
| `etikett` | footnote semibold | Chips, statuslinjer |
| `liten` | caption medium | Hint, metadata |
| `tall` / `tallLiten` | title/headline black + monospaced digits | Poeng og bud (hopper ikke når sifre endres) |

## Avstand og form

- Avstandsskala: 4 / 8 / 12 / 16 / 24 / 32 (`DS.Avstand.xs–xxl`).
- Hjørneradier: 10 / 14 / 20 / 28 (`DS.Radius.s–xl`) – alltid `continuous`.
- Trykkflater: minst **48 pt** (`DS.Mål.minTrykk`); primærknapper 54 pt.

## Komponenter

| Komponent | Fil | Bruk |
|-----------|-----|------|
| `BTButtonStyle` | Theme.swift | Alle knapper (farge + stor/liten) |
| `PapirPanel` | Theme.swift | Standard innholdspanel |
| `SnakkeBoble` | Theme.swift | Replikker og veiledning |
| `MaskotView` | Theme.swift | Benjamin Franklin-læremesteren |
| `OpponentPortrett` / `TrekkLinje` | Theme.swift | Lederprofiler (Civ-stil) |
| `CardView` / `CardBackView` / `MiniKort` | Game/, Onboarding/ | Spillkort i tre størrelser |
| `HandActionArea` | Game/ | Tommelsonen: hånd + primærhandling (delt offline/online) |

## Motion (`DS.Bevegelse`)

Tre fjærkurver – og bare disse tre:

- `rask` (0,22 s): trykk-respons på knapper og kortvalg.
- `standard` (0,32 s): kort inn på bordet, paneler inn fra bunnen, det meste.
- `myk` (0,45 s): rundeslutt og seiersskjermer.

Transisjoner: `kortInn` (skala+fade), `panelInn` (fra bunnen), `bannerInn`
(fra toppen). Regler: bevegelse skal **aldri blokkere input**, alt skal
kunne avbrytes, og pacing i spillet (AI-pauser, stikk-visning) er en del av
motion-designet – se `GameViewModel.aiLøkke`.

## UX-prinsipper

### Bestemor-testen
1. **Hver gest har en synlig knapp-ekvivalent.** Sveip-opp for å spille
   kort er en snarvei; den store «Spill kortet»-knappen gjør samme jobb.
2. **To-trinns handlinger der feil koster:** velg kort → bekreft. Ingen
   kort spilles ved ett enkelt uhell-trykk.
3. **Én tydelig primærhandling per skjerm**, alltid rød, alltid nederst.
4. Dynamic Type støttes overalt; «Store kort»-innstilling for hånden.
5. Klarspråk på norsk – aldri sjargong («Budet røk!», ikke «Kontrakt tapt»).

### Tommelsonen (portrett først)
Skjermen er delt i tre soner etter rekkevidde med én hånd:

```
┌──────────────────────────┐
│  Motstandere + info      │  Se, aldri trykke
│  (øverste tredjedel)     │
├──────────────────────────┤
│  Bordet / stikket        │  Se, sjelden trykke
│  (midten)                │
├──────────────────────────┤
│  Bud-/trumfpanel         │  ALL interaksjon:
│  Hånden                  │  paneler, kort og
│  [ Spill kortet ]        │  primærknapp
└──────────────────────────┘
```

Bud- og trumfpanelene glir inn fra bunnen (`panelInn`) og legger seg rett
over hånden – tommelen flytter seg aldri ut av nederste tredjedel i løpet
av et helt parti. Landskapsmodus skal være spillbar (layouten reflower),
men portrett er designmålet.

### Informasjonshierarki på bordet
Med liten skjerm og tre ting å følge (egne kort, bordet, motstanderne):
- Motstanderne er **kompakte statuskort** øverst: portrett, poeng, stikk,
  siste bud – aldri interaktive.
- Bordet i midten viser bare stikket + tynne info-chips (trumf, etterlyst
  kort, budlagets fremdrift, stikknummer).
- Hånden er størst, nederst, med lovlige kort løftet og ulovlige nedtonet.

## Neste designarbeid (assets)
- Rive-animerte karakterportretter (idle/glede/frustrasjon per president).
- Egne lydfiler til erstatning for systemlydene i `Feedback.swift`.
- App-ikon og kortbaksider med americana-motiv.

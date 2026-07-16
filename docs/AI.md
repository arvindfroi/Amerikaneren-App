# Slik tenker CPU-ene

All AI ligger i `AI/AIPlayer.swift` og er ren heuristikk – ingen søk, ingen
simulering. Det gjør den rask, forutsigbar å teste, og lett å justere.

## Håndvurdering (`estimerStikk`)

For hver mulige trumffarge estimeres forventede stikk:

- **Trumflengde**: ~0,55 stikk per trumfkort, med bonus over 3 kort
  (lengde er viktigere enn honnører i Amerikaner).
- **Honnører**: Ess ≈ 1 stikk (0,9 utenfor trumf), konge 0,65 med dekning,
  dame 0,35 i lange farger.
- **Renons/singelton** i sidefarger gir stjålne stikk skalert mot antall
  trumf på hånden.

`besteTrumf` velger fargen med høyest estimat.

## Budgivning (`velgBud`)

```
estimat = håndestimat + 2.0 (forventet makkerbidrag)
        + (aggresjon − 0.5) × 2.5     ← hoppes over på President
        + støy fra vanskelighetsgrad   ← hoppes over på President
```

Byr laveste lovlige tallbud så lenge det er ≤ eget estimat, ellers pass.

- **Amerikaner-melding**: krever solo-estimat ≥ 11,5 *og* et
  personlighetsslag mot `storhetsdrøm`. På President meldes den kun med
  reell dekning (≥ 12,5), uten terningkast.
- **Bløff**: bevisst nesten borte – man bløffer lite i Amerikaner. Kun en
  sjelden (`bløff × 0,15`) overbydning på ett hakk. Aldri på President.

## Kortvalg (`velgKort`)

Prioritering når man ikke spiller ut:

1. Makkeren har stikket → legg lavest (lojalitet ≥ 0,35 eller President;
   sistemann gjør det alltid).
2. Kan vinne → legg **billigste vinnende kort**. Risikovillige (< President)
   kan tidlig i runden gamble på å spare et ess.
3. Ellers → legg lavest (trumf regnes alltid som dyrest å kaste).

Utspill:

- **Budgiverlaget trekker trumf** de første rundene – hvor lenge styres av
  `risiko` (3–5 stikk); på President trekkes trumf så lenge motstanderne
  faktisk har trumf igjen (enkel kortteling på spilte kort).
- Deretter spilles sikre vinnere: ess, eller kort som er blitt høyest i
  fargen fordi alt over er spilt (kortteling).
- Ellers lavest.

## Vanskelighetsgrader

| Grad | Budstøy | Feilspillsjanse | Personlighet |
|------|---------|-----------------|--------------|
| Lett | ±2,2 | 35 % tilfeldig lovlig kort | full effekt |
| Middels | ±1,2 | 15 % | full effekt |
| Vanskelig | ±0,5 | 4 % | full effekt |
| **President** | 0 | 0 | **skrus helt av** |

President-regelen er absolutt: `AIDifficulty.spillerPerfekt` kortslutter
alle personlighetsjusteringer, så Onkel Sam (og alle andre på President-
nivå) byr rent på estimatet og spiller alltid det heuristisk beste kortet.

## Personligheter (Civ-stil)

Trekkene (0–1) vises i lederprofilen og styrer primært **budgivning og
trumfbruk** – ikke fusk eller skjult informasjon. AI-en ser aldri andres
kort; den vet bare hva som er spilt (åpen informasjon rundt bordet).

| Trekk | Effekt |
|-------|--------|
| Aggresjon | Skyver budestimatet opp/ned |
| Risiko | Hvor lenge laget trekker trumf; gambling med storkort |
| Bløff | Sjelden overbydning – liten effekt med vilje |
| Lojalitet | Om man legger lavt når makkeren har stikket |
| Storhetsdrøm | Sannsynligheten for å melde Amerikaner |

Eksempler: Theodore Roosevelt (aggresjon 0,95) byr over evne, Donald Trump
(aggresjon 1,0 + storhetsdrøm 1,0) melder Amerikaner ved første anledning,
George Washington (bløff 0,0) byr aldri uten dekning, Eisenhower
(risiko 0,2) spiller konservativt og planmessig.

## Lagforståelse

`erPåMittLag` bruker kun informasjon setet faktisk har: budgiver er kjent
for alle, en avslørt makker likeså, mens en **uavslørt makker** vet selv at
den er på budgiverlaget – forsvarerne behandler den som medspiller inntil
ønskekortet legges. Ingen AI vet noe et menneske i samme sete ikke ville
visst.

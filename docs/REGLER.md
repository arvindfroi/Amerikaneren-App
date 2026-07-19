# Reglene slik de er implementert

Kilder: [Wikipedia: Amerikaner (kortspill)](https://no.wikipedia.org/wiki/Amerikaner_(kortspill))
og [kortregler.no/amerikaner](https://kortregler.no/amerikaner).

## Grunnoppsett

- 4 spillere (motorens standard – «best med 4» ifølge kortregler.no).
- **Byttekort-varianten er standard**: hver spiller får 12 kort, og de
  siste 4 legges i en talong som budvinneren bytter med.
- Ess er høyest, to er lavest. Ingen jokere.
- Klassiske regler (13 kort, ingen talong) støttes via
  `GameRules.medByttekort = false`.
- Companion-modus støtter 3–6 spillere med samme poenglogikk.

## Budrunden

- Starter hos spilleren til venstre for giveren, går med klokka.
- Minste bud er **5**, høyeste er antall stikk i runden (12 med
  byttekort, 13 uten).
- Hvert bud må være høyere enn forrige; pass er alltid lov, og den som
  passer er ute av budrunden.
- **«Amerikaner»** er en egen melding: ta alle stikkene alene, uten trumf
  og uten makker. Den slår alle tallbud og kan ikke overbys – budrunden
  avsluttes umiddelbart.
- Passer alle fire, deles det ut på nytt med neste giver.

## Byttekortene

- Budvinneren tar opp talongen (16 kort på hånden) og **vraker 4
  valgfrie kort**, skjult for de andre. Vraket er ute av runden.
- Dette gjelder også ved Amerikaner-melding (implementasjonsvalg – den
  vanligste talong-praksisen er at budvinneren alltid får kortene).

## Trumf og hemmelig makker

- Budvinneren velger trumffarge og **ber om ett kort** i den fargen som
  de ikke har selv (typisk høyeste trumf de mangler).
- Spilleren som sitter med kortet blir budvinnerens **hemmelige makker**.
- Makkerplikt: i **første stikk** må makkeren legge det etterlyste kortet
  ved første lovlige anledning (`GameEngine.lovligeKort` returnerer da kun
  det kortet). Da avsløres makkeren for alle.
- Motoren nekter budvinneren å be om et kort de selv har på hånden – men
  **ikke** et kort de selv vraket: å etterlyse et dødt kort er en bevisst
  (og lovlig) måte å spille alene på. Ligger det etterlyste kortet i
  vraket uten at budvinneren visste det, spiller budvinneren uvitende
  alene – ingen andre får vite at kortet er dødt.

## Stikkspillet

- Budvinneren spiller ut først. Følg farge om mulig; ellers fritt
  (trumfe eller kaste).
- Stikket vinnes av høyeste trumf, eller høyeste kort i utspillsfargen
  om ingen trumf er lagt. Vinneren spiller ut i neste stikk.
- Ved Amerikaner-melding spilles hele runden **uten trumf**.

## Poeng

| Situasjon | Budgiver + makker | Øvrige spillere |
|-----------|-------------------|-----------------|
| Laget tar minst budet i stikk | **+bud** hver | +1 per eget stikk |
| Laget feiler | **−bud** hver | +1 per eget stikk |
| Amerikaner klart (alle stikk) | +100 til solisten | (har null stikk) |
| Amerikaner feilet | −100 til solisten | +1 per eget stikk |

- Budgiverlaget får poeng lik **budet**, ikke antall stikk – overstikk gir
  ingenting ekstra (slik begge kildene beskriver).
- **Først til 100 poeng vinner.** Sjekkes etter hver runde.
- Ved poenglikhet på/over 100 i samme runde vinner budgiversiden fra den
  runden (vanlig husregel; kildene sier ikke noe eksplisitt om likhet).

## Bevisste valg og avvik

- Målet er endret fra kildenes 52 til **100 poeng**, og
  Amerikaner-gevinsten er skalert tilsvarende (±100) slik at en klart
  Amerikaner fortsatt vinner partiet på flekken.
- Byttekort-varianten er slått **på** som standard (kortregler.no
  beskriver den som valgfri regel).
- 3-, 5- og 6-spillervarianter av selve motoren er ikke implementert
  (companion-modusen dekker dem for fysisk spill). `GameRules` er
  parametrisert på spillertall, så det er forberedt.
- Makkerplikten er tolket som «må legge kortet i første stikk hvis det er
  lovlig» – kildene sier «må gi fra seg kortet», og dette er den vanligste
  praktiseringen.

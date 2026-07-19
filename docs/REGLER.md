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
- **«Amerikaner»** er en egen melding: laget (budvinner + hemmelig makker)
  skal ta **alle stikkene** – med trumf og makker som vanlig. Den slår
  alle tallbud, men kan overbys av solo-amerikaner.
- **«Solo-amerikaner»** er den høyeste meldingen: ta alle stikkene **helt
  alene**. Det spilles fortsatt med trumf, og man KAN etterlyse ett kort
  som må legges i første stikk – men ingen makker og ingen hjelp etterpå.
  Solo kan ikke overbys, så budrunden avsluttes umiddelbart.
- Passer alle fire, deles det ut på nytt med neste giver.

## Byttekortene

- Budvinneren tar opp talongen (16 kort på hånden) og **vraker 4
  valgfrie kort**, skjult for de andre. Vraket er ute av runden.
- Dette gjelder alle meldinger – også Amerikaner og solo-amerikaner.

## Trumf og hemmelig makker

- Budvinneren velger trumffarge og **ber om ett kort** i den fargen
  (typisk høyeste trumf de mangler).
- Ved tallbud og Amerikaner blir spilleren som sitter med kortet
  budvinnerens **hemmelige makker**. Ved solo-amerikaner er
  etterlysningen valgfri og gir ingen makker – kortet må bare legges.
- Makkerplikt: i **første stikk** må den som har kortet legge det ved
  første lovlige anledning (`GameEngine.lovligeKort` returnerer da kun
  det kortet). Da avsløres makkeren for alle – og «det første stikket»
  er i praksis stikket der kortet tvinges fram; vinneren av det (som
  regel makkeren, med den høye trumfen) spiller ut i neste stikk.
- Det er **ikke lov** å etterlyse et kort man har på hånden eller selv
  har vraket – det etterlyste kortet sitter alltid hos en motspiller.

## Stikkspillet

- Budvinneren spiller ut først. Følg farge om mulig; ellers fritt
  (trumfe eller kaste).
- Stikket vinnes av høyeste trumf, eller høyeste kort i utspillsfargen
  om ingen trumf er lagt. Vinneren spiller ut i neste stikk.
- Det spilles med trumf i alle runder – også ved Amerikaner og
  solo-amerikaner.

## Poeng

Budvinneren får alltid **dobbelt så mye** som makkeren.

| Situasjon | Budvinner | Makker | Øvrige spillere |
|-----------|-----------|--------|-----------------|
| Tallbud n klart | **+2n** | **+n** | +1 per eget stikk |
| Tallbud n feilet | **−2n** | **−n** | +1 per eget stikk |
| Amerikaner klart (alle stikk) | **+50** | **+25** | (har null stikk) |
| Amerikaner feilet | **−50** | **−25** | +1 per eget stikk |
| Solo-amerikaner klart | **+100** | – | (har null stikk) |
| Solo-amerikaner feilet | **−100** | – | +1 per eget stikk |

- Budlaget får poeng etter **budet**, ikke antall stikk – overstikk gir
  ingenting ekstra.
- Amerikaner-satsene skaleres med målet: ±målPoeng/2 og ±målPoeng/4
  (solo ±målPoeng), så en klart solo-amerikaner vinner alltid på flekken.
- **Først til 100 poeng vinner.** Sjekkes etter hver runde.
- Ved poenglikhet på/over 100 i samme runde vinner budgiversiden fra den
  runden (vanlig husregel; kildene sier ikke noe eksplisitt om likhet).

## Bevisste valg og avvik (husregler)

- Reglene over følger husreglene til spillets eier der de avviker fra
  kildene: byttekort som standard, mål på 100 poeng, Amerikaner med
  makker/trumf pluss egen solo-melding, dobbel poengsats til budvinner,
  og forbud mot å etterlyse vrakede kort.
- 3-, 5- og 6-spillervarianter av selve motoren er ikke implementert
  (companion-modusen dekker dem for fysisk spill). `GameRules` er
  parametrisert på spillertall, så det er forberedt.
- Makkerplikten er tolket som «må legge kortet i første stikk hvis det er
  lovlig» – kildene sier «må gi fra seg kortet», og dette er den vanligste
  praktiseringen.

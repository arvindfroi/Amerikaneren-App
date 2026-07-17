# Åpne design- og UX-beslutninger

Arbeidsdokument. Ingenting av dette er låst – designsystemet (`DS`) er
bygget som tokens nettopp for at retningen kan endres billig senere.
Skriv gjerne rett i dette dokumentet, eller bare si hva du lander på.

Status: **utkast – venter på retningsvalg.**

## 1. Visuell identitet

Dagens utkast er «Brain Training møter americana» (papir/blekk/rød).
Alternativer å vurdere før vi lager assets:

- **A. Papir & blekk (dagens):** varmt, håndtegnet, vennlig. Passer
  bestemor-målet. Risiko: kan bli «stillebord»-kjedelig uten gode assets.
- **B. Filtgrønt kortbord:** klassisk kortspill-følelse (grønn filt, tre,
  gullkanter). Mer «kasino», mindre Brain Training.
- **C. Flat retro-americana:** 50-talls plakatstil, sterke flater, stjerner
  og buer. Mest karakter, mest jobb å holde konsekvent.

→ Påvirker: fargetokens, kortdesign, portrettstil, Rive-assets.

## 2. Kort-interaksjon på bordet

Dagens utkast: to-trinn (trykk = velg, trykk igjen / dra opp / stor knapp
= spill).

- **A. To-trinn for alle (dagens):** tryggest, ett ekstra trykk per kort.
- **B. Ett-trykk med angrevindu:** kortet spilles direkte, liten «Angre»-
  knapp i 1–2 sekunder før AI-en reagerer.
- **C. Innstilling:** «Bekreft kortvalg» av/på – to-trinn som standard,
  ekspertene skrur det av.

→ Anbefaling når vi kommer dit: C.

## 3. Gestomfang

Hvilke gester skal finnes (alle med knapp-ekvivalent)?

- Dra-opp for å spille kort (finnes i utkastet)
- Sveip ned på bordet for å se forrige stikk igjen?
- Langt trykk på motstander for lederprofil?
- Dobbelttrykk for «beste lovlige kort»-forslag (treningshjul)?

## 4. Navigasjonsmodell

- **A. Meny-liste (dagens):** enkel, tydelig, litt kjedelig.
- **B. «Bord»-hub:** ett stort illustrert rom der modusene er objekter
  (kortstokk = spill, pokal = kampanje, notatblokk = companion).
- **C. Tab-bar:** Spill / Kampanje / Statistikk / Mer.

## 5. Onboarding-flyt

Dagens: velkomst → navn → 3 regelkort → valgfri tutorial. Åpent:

- Skal førstegangsbrukeren ledes rett inn i et guidet parti i stedet for
  regelkort (learning by doing)?
- Skal navn/Game Center-innlogging utsettes til det trengs?

## 6. Spillbordets informasjonstetthet

- Hvor mye skal vises alltid vs. på forespørsel? (budhistorikk, poengtavle,
  «etterlyst kort», budlagets fremdrift)
- Skal motstander-raden ha faste plasser rundt bordet (romfølelse) eller
  forbli en rad øverst (kompakthet)?

## 7. Karakter-assets (når retning i pkt. 1 er valgt)

- Rive (interaktive, state machines: idle/glede/sinne) vs. Lottie
  (lineære klipp) vs. statiske illustrasjoner med SwiftUI-animasjon.
- Hvor mye skal karakterene «leve» under spill uten å stjele fokus?

## 8. Lyd

- Tone: lun og treaktig (papir-identitet) vs. sprett og arkade?
- Egen musikk i meny/kampanje, eller kun effekter?

## Slik jobber vi videre

1. Velg retning i pkt. 1 og 4 først – de styrer mest.
2. Jeg lager 2–3 raske varianter i kode (billig med tokens) som du kan
   se på Appetize og velge mellom.
3. Deretter låser vi DESIGN.md fra «utkast» til «gjeldende», og først da
   bestiller/lager vi assets.

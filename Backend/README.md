# Backend for treningsdata

Ingest-tjenesten som tar imot anonyme partiopptak fra appen og gjør dem
tilgjengelige for treningsharnessen. Koden ligger i `valtown/main.ts` og
er skrevet for [Val Town](https://www.val.town) (gratis, null drift),
men logikken er ren TypeScript/Deno – bytt ut `std/sqlite`-importen med
en annen libsql/sqlite-klient for å kjøre den hvor som helst.

## Dataflyt

```
Appen (med samtykke)                    Backenden                Treneren
────────────────────                    ─────────                ────────
Rundeopptak fanges ved rundeslutt
  → verifiseres ved avspilling
  → kølegges på disk (maks 200)
  → POST /v1/opptak i småbatcher   →    strukturell validering
                                        idempotent SQLite-lagring
                                                                  GET /v1/eksport (NDJSON)
                                                                  → avspilles og re-verifiseres
                                                                  → (situasjon → fasit)-par
                                                                  → treningsdatasett
```

Formatet er rått med vilje: hele utdelingen + alle valg, slik at
fremtidige nett kan regenerere trekkuttrekk uansett hvordan kodingen
endrer seg. Se `docs/DATA.md` for felt-for-felt-beskrivelse og
personvernvurderingen.

## Endepunkter

| Metode | Sti | Autentisering | Gjør |
|--------|-----|---------------|------|
| POST | `/v1/opptak` | `X-App-Nokkel` | Tar imot `{"partier": [Partiopptak…]}` |
| GET | `/v1/eksport?siden=&grense=` | `X-Admin-Nokkel` | NDJSON, eldste først, inkrementell via `X-Neste-Siden`-headeren |
| GET | `/v1/helse` | åpen | Antall partier/runder, siste mottak |

## Robusthet

- **Idempotent**: parti-UUID er primærnøkkel med `INSERT OR IGNORE`;
  appen kan sende samme batch så mange ganger den vil (og gjør det ved
  nettverksfeil). Duplikater svarer likevel 200 så klientkøen tømmes.
- **Validering i tre ledd**: appen spiller av hvert opptak mot motoren
  før sending, backenden sjekker strukturen (én full kortstokk per
  runde, riktige antall, gyldige kort), og treneren spiller av alt på
  nytt ved import. Tuklede eller korrupte opptak når aldri treningen.
- **Grenser**: 2 MB per kall, 20 partier per kall, nødbrems på 2 000
  partier per døgn. 4xx-svar får appen til å forkaste ugyldige køfiler
  i stedet for å prøve dem evig.

## Deploy på Val Town (5 minutter)

1. Opprett en val (f.eks. `amerikaneren-data`) og lim inn
   `valtown/main.ts` som en **HTTP**-fil.
2. Sett miljøvariabler på valen:
   - `APP_NOKKEL` – delt nøkkel appen sender (samme verdi som
     `InnsamlingKonfig.produksjon.appNøkkel` i
     `Amerikaneren/Innsamling/Innsamler.swift`).
   - `ADMIN_NOKKEL` – hemmelig nøkkel kun treneren bruker. Lag en lang
     tilfeldig streng, f.eks. `openssl rand -hex 24`.
3. Kopier filens endepunkt-URL og sett den inn som
   `InnsamlingKonfig.produksjon.endepunkt` (med `/v1/opptak` på slutten).
4. Sjekk `GET /v1/helse` i nettleseren.

Inntil endepunktet er satt samler appen opptak i en lokal, avgrenset kø
og laster dem opp automatisk første gang et endepunkt finnes.

## Hente data til trening

```sh
curl -H "X-Admin-Nokkel: $ADMIN_NOKKEL" \
  "https://<val-url>/v1/eksport?grense=500" >> partier.ndjson
# Gjenta med ?siden=<X-Neste-Siden-headeren> til svaret er tomt.
```

NDJSON-filen mates rett inn i treningsharnessens `importer`-kommando,
som spiller av hvert parti gjennom den ekte motoren og skriver
treningsdatasett. Se `docs/DATA.md`.

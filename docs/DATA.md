# Datainnsamling for trening

Når spillere samtykker, samles anonyme partiopptak inn som treningsdata
for AI-en. Dette dokumentet beskriver hva som samles, hvordan kjeden
henger sammen, og hvorfor den er robust.

## Hva samles – og hva samles aldri

Et **rundeopptak** (`Amerikaneren/Innsamling/Opptak.swift`) er den
komplette, rå runden:

| Felt | Innhold |
|------|---------|
| `hender` | de fire utdelte hendene |
| `talon` | de fire byttekortene |
| `førsteBudgiver` | hvem som åpnet budrunden |
| `bud` | hele budrunden i rekkefølge, med pass |
| `kastet` | budvinnerens vrak |
| `trumf`, `ønsket` | trumfvalget og etterlysningen |
| `spilte` | alle 48 kort i nøyaktig spilt rekkefølge |
| `resultat` | stikk, klarte/røk, poengendringer |

Et **partiopptak** samler rundene med reglene, sluttpoeng, vinner og en
`Seteinfo` per sete: *om* det satt et menneske der, ellers CPU-nivået.

**Aldri med**: navn, spillernavn, Game Center-ID-er, enhets-ID-er eller
klokkeslett (kun dato). Opptaket kan ikke føres tilbake til en person –
det er bare kort og trekk.

Formatet er rått med vilje. Nettets trekkuttrekk (koding av situasjonen)
kommer til å endre seg; rå runder kan alltid avspilles på nytt og
kodes om, så gamle data blir aldri verdiløse.

## Samtykke

- Av som standard. Slås på i Innstillinger → «Bidra til smartere
  motstandere», med klartekst om hva som deles.
- Slås samtykket av, slettes den lokale sendekøen umiddelbart.
- Online-partier fanges av verten; opptaket er like anonymt der (kun
  «menneske/CPU» per sete).

## Kjeden, ledd for ledd

```
Motoren      GameEngine husker utdelingen gjennom runden
   ↓         (utdelteHender/utdeltTalon/førsteBudgiverIRunden)
Opptak       Rundeopptak(fra:) fanger ferdig runde; Partiopptak ved partislutt
   ↓
Verifisering spillAv() spiller runden av i en fersk motor og sjekker
   ↓         HVERT trekk mot reglene + resultatet mot det lagrede
Kø           JSON-filer i Application Support; maks 200 partier,
   ↓         eldste ryddes først; overlever at appen drepes
Opplasting   småbatcher via URLSession når appen er aktiv;
   ↓         nettverksfeil → ligger til neste forsøk; 4xx → forkastes
Backend      strukturell validering, idempotent SQLite-lagring
   ↓         (Backend/valtown/main.ts – se Backend/README.md)
Trener       `trainer importer` avspiller og RE-verifiserer alt,
             høster (situasjon → fasit)-par → treningsdatasett
```

Verifiseringen skjer altså i tre uavhengige ledd (app, backend,
trener). Ett ulovlig trekk hvor som helst, og hele partiet vrakes –
treningen kan ikke forgiftes.

## Status og hva som gjenstår

- [x] Motoropptak, verifisert avspilling, kø, samtykke-UI, opplaster
- [x] Backend-kode klar i `Backend/valtown/` (validering, idempotens,
      NDJSON-eksport) – testet lokalt via `trainer syntetisk`
- [x] `trainer importer` + `trainer syntetisk` (hele kjeden testet
      ende-til-ende, inkl. at tuklede opptak avvises)
- [ ] Deploy av backenden (hostingvalg utsatt – Val Town-oppskrift på
      5 minutter i Backend/README.md) og sette
      `InnsamlingKonfig.produksjon.endepunkt`

Inntil endepunktet er satt samler appen opptak lokalt (avgrenset kø) og
laster opp automatisk første gang et endepunkt finnes – ingen data går
tapt av at backenden kommer senere.

## Hvorfor menneskedata er verdt det

Nettet er destillert fra MesterAI-søk. Ekte partier gir tre ting søket
ikke gir:

1. **Menneskelige mønstre å modellere**: makker-modellering og
   signalforståelse (neste AI-løft) trenger ekte menneskers valg for å
   kalibrere «hvordan spiller folk faktisk».
2. **Fordelingen av virkelige situasjoner**: selvspill konsentrerer seg
   om posisjoner søkeboten selv havner i; mennesker havner andre steder.
3. **Vanskelige fasiter gratis**: hver runde er også et nytt
   (utdeling → utfall)-datapunkt for verdinettes kalibrering.

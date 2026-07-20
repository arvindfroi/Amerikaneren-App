// Ingest-backend for anonyme Amerikaneren-partiopptak (treningsdata).
//
// Skrevet for Val Town (Deno + std/sqlite), men logikken er ren TypeScript:
// bytt ut sqlite-importen med en annen libsql/sqlite-klient for å kjøre den
// hvor som helst. Se Backend/README.md for deploy-oppskrift.
//
// Endepunkter:
//   POST /v1/opptak   – appen leverer partier   (X-App-Nokkel)
//   GET  /v1/eksport  – treneren henter NDJSON  (X-Admin-Nokkel)
//   GET  /v1/helse    – enkel driftsstatus      (åpen, kun tall)
//
// Robusthet:
//   - Delt appnøkkel + harde grenser for kroppsstørrelse og antall partier.
//   - Strukturell validering av hvert parti: nøyaktig én full kortstokk
//     per runde, riktige antall, gyldige kort-IDer. (Full regelverifisering
//     skjer i tillegg i Swift – både i appen før sending og i treneren
//     ved import – så tuklede opptak stoppes uansett.)
//   - Idempotent lagring: parti-UUID er primærnøkkel, INSERT OR IGNORE.
//     Appen kan trygt sende samme batch flere ganger.
//   - Grov volumbrems per døgn så en løpsk klient ikke kan fylle lagringen.

import { sqlite } from "https://esm.town/v/std/sqlite/main.ts";

const MAKS_KROPP = 2_000_000;        // bytes per forespørsel
const MAKS_PARTIER_PER_KALL = 20;
const MAKS_PARTIER_PER_DØGN = 2_000; // nødbrems, ikke kvote
const GYLDIGE_VERSJONER = new Set([1]);

// Kort-ID-er slik Swift-koden serialiserer dem: "♠14", "♥2", …
const FARGER = ["♠", "♥", "♦", "♣"];
const KORT_ID = new RegExp(`^[${FARGER.join("")}](?:[2-9]|1[0-4])$`);

async function sikreSkjema() {
  await sqlite.execute(`CREATE TABLE IF NOT EXISTS partiopptak (
    id TEXT PRIMARY KEY,
    mottatt TEXT NOT NULL,
    versjon INTEGER NOT NULL,
    modus TEXT,
    dag TEXT,
    antall_runder INTEGER NOT NULL,
    json TEXT NOT NULL
  )`);
  await sqlite.execute(
    `CREATE INDEX IF NOT EXISTS idx_partiopptak_mottatt ON partiopptak (mottatt)`,
  );
}

type Kort = { suit: string; rank: number };

function kortId(k: unknown): string | null {
  if (typeof k !== "object" || k === null) return null;
  const { suit, rank } = k as Kort;
  const id = `${suit}${rank}`;
  return KORT_ID.test(id) ? id : null;
}

/// Strukturell validering av ett parti. Returnerer null hvis alt er i
/// orden, ellers en kort feilbeskrivelse.
function validerParti(p: any): string | null {
  if (typeof p !== "object" || p === null) return "parti er ikke et objekt";
  if (typeof p.id !== "string" || !/^[0-9A-Fa-f-]{36}$/.test(p.id)) {
    return "mangler gyldig id";
  }
  if (!GYLDIGE_VERSJONER.has(p.versjon)) return `ukjent versjon ${p.versjon}`;
  if (!Array.isArray(p.runder) || p.runder.length < 1 || p.runder.length > 200) {
    return "ugyldig antall runder";
  }
  if (!Array.isArray(p.seter) || p.seter.length !== 4) return "ugyldige seter";
  const regler = p.regler ?? {};
  const kortPerSpiller = regler.medByttekort === false ? 13 : 12;
  const talongStørrelse = regler.medByttekort === false ? 0 : 4;

  for (const [i, runde] of p.runder.entries()) {
    const hvor = `runde ${i}`;
    if (!Array.isArray(runde.hender) || runde.hender.length !== 4) {
      return `${hvor}: ugyldige hender`;
    }
    const alle: string[] = [];
    for (const hånd of runde.hender) {
      if (!Array.isArray(hånd) || hånd.length !== kortPerSpiller) {
        return `${hvor}: feil håndstørrelse`;
      }
      for (const k of hånd) {
        const id = kortId(k);
        if (!id) return `${hvor}: ugyldig kort`;
        alle.push(id);
      }
    }
    if (!Array.isArray(runde.talon) || runde.talon.length !== talongStørrelse) {
      return `${hvor}: ugyldig talong`;
    }
    for (const k of runde.talon) {
      const id = kortId(k);
      if (!id) return `${hvor}: ugyldig talongkort`;
      alle.push(id);
    }
    if (alle.length !== 52 || new Set(alle).size !== 52) {
      return `${hvor}: utdelingen er ikke én full kortstokk`;
    }
    if (!Array.isArray(runde.spilte) || runde.spilte.length !== 4 * kortPerSpiller) {
      return `${hvor}: feil antall spilte kort`;
    }
    const spilteIder = runde.spilte.map(kortId);
    if (spilteIder.some((id: string | null) => id === null)) {
      return `${hvor}: ugyldig spilt kort`;
    }
    if (new Set(spilteIder).size !== spilteIder.length) {
      return `${hvor}: samme kort spilt to ganger`;
    }
    if (!Array.isArray(runde.bud) || runde.bud.length < 1 || runde.bud.length > 60) {
      return `${hvor}: ugyldig budrunde`;
    }
  }
  return null;
}

function svar(status: number, kropp: unknown): Response {
  return new Response(JSON.stringify(kropp), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function taImot(req: Request): Promise<Response> {
  const nøkkel = Deno.env.get("APP_NOKKEL");
  if (!nøkkel || req.headers.get("X-App-Nokkel") !== nøkkel) {
    return svar(401, { feil: "ugyldig appnøkkel" });
  }
  const rå = await req.text();
  if (rå.length > MAKS_KROPP) return svar(413, { feil: "for stor forespørsel" });

  let kropp: any;
  try {
    kropp = JSON.parse(rå);
  } catch {
    return svar(400, { feil: "ugyldig JSON" });
  }
  const partier = kropp?.partier;
  if (!Array.isArray(partier) || partier.length === 0) {
    return svar(400, { feil: "mangler partier" });
  }
  if (partier.length > MAKS_PARTIER_PER_KALL) {
    return svar(400, { feil: "for mange partier i ett kall" });
  }

  await sikreSkjema();

  // Grov nødbrems: ikke ta imot mer enn MAKS_PARTIER_PER_DØGN siste døgn.
  const iGår = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
  const volum = await sqlite.execute({
    sql: "SELECT COUNT(*) AS n FROM partiopptak WHERE mottatt > ?",
    args: [iGår],
  });
  if ((volum.rows[0] as any).n >= MAKS_PARTIER_PER_DØGN) {
    return svar(503, { feil: "døgnvolum nådd, prøv igjen senere" });
  }

  let mottatt = 0;
  let avvist = 0;
  const nå = new Date().toISOString();
  for (const parti of partier) {
    const feil = validerParti(parti);
    if (feil) {
      avvist++;
      console.log(`avviste parti: ${feil}`);
      continue;
    }
    const resultat = await sqlite.execute({
      sql: `INSERT OR IGNORE INTO partiopptak
            (id, mottatt, versjon, modus, dag, antall_runder, json)
            VALUES (?, ?, ?, ?, ?, ?, ?)`,
      args: [
        parti.id.toLowerCase(),
        nå,
        parti.versjon,
        String(parti.modus ?? "").slice(0, 20),
        String(parti.dag ?? "").slice(0, 10),
        parti.runder.length,
        JSON.stringify(parti),
      ],
    });
    mottatt += resultat.rowsAffected ?? 0;
  }
  // 200 også når alt var duplikater: klienten skal slette køfilene sine.
  return svar(200, { mottatt, avvist, duplikater: partier.length - mottatt - avvist });
}

/// NDJSON-eksport for treneren: ett parti per linje, eldste først.
/// ?siden=ISO-tidspunkt gir inkrementell henting; ?grense=N (maks 500).
async function eksporter(req: Request): Promise<Response> {
  const nøkkel = Deno.env.get("ADMIN_NOKKEL");
  if (!nøkkel || req.headers.get("X-Admin-Nokkel") !== nøkkel) {
    return svar(401, { feil: "ugyldig adminnøkkel" });
  }
  await sikreSkjema();
  const url = new URL(req.url);
  const siden = url.searchParams.get("siden") ?? "";
  const grense = Math.min(Number(url.searchParams.get("grense") ?? 200) || 200, 500);
  const resultat = await sqlite.execute({
    sql: `SELECT mottatt, json FROM partiopptak
          WHERE mottatt > ? ORDER BY mottatt, id LIMIT ?`,
    args: [siden, grense],
  });
  const linjer = resultat.rows.map((r: any) => r.json).join("\n");
  const sisteMottatt = resultat.rows.length
    ? (resultat.rows[resultat.rows.length - 1] as any).mottatt
    : siden;
  return new Response(linjer, {
    headers: {
      "Content-Type": "application/x-ndjson; charset=utf-8",
      "X-Neste-Siden": sisteMottatt,
      "X-Antall": String(resultat.rows.length),
    },
  });
}

async function helse(): Promise<Response> {
  await sikreSkjema();
  const resultat = await sqlite.execute(
    `SELECT COUNT(*) AS partier, COALESCE(SUM(antall_runder), 0) AS runder,
            COALESCE(MAX(mottatt), '') AS sist
     FROM partiopptak`,
  );
  const rad = resultat.rows[0] as any;
  return svar(200, { status: "ok", partier: rad.partier, runder: rad.runder, sist: rad.sist });
}

export default async function (req: Request): Promise<Response> {
  const sti = new URL(req.url).pathname;
  try {
    if (req.method === "POST" && sti === "/v1/opptak") return await taImot(req);
    if (req.method === "GET" && sti === "/v1/eksport") return await eksporter(req);
    if (req.method === "GET" && sti === "/v1/helse") return await helse();
    return svar(404, { feil: "ukjent sti" });
  } catch (feil) {
    console.error(feil);
    return svar(500, { feil: "intern feil" });
  }
}

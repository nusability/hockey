// Smash Hockey telemetry collector — spec §18, ADR 0009.
//
// One route per table, and **no column list in this file**. The tables, their columns, the order and
// the declared value sets are read at boot from `columns.json`, which tools/generate-data.py writes
// from shared/data/telemetry.toml — the same declaration the two apps' record types come from.
//
// That is the entire design, and it exists because of a documented failure next door:
// ../flashybird's collector kept its columns by hand, and for months `platform`, `language` and the
// five columns its difficulty question grouped on were *sent and not inserted*. In its own words —
// "a column missing from this list is not an error at any layer; it is a default quietly standing in
// for a measurement." A column cannot go missing here, because nothing here names one.
//
// Deliberately small: accept a batch, write it, answer 204. The client drops a failed send rather
// than stalling a frame (A0, A2), so nothing clever here buys the game anything.
//
//   DATABASE_URL=postgres://…  PORT=3014  SH_INGEST_TOKEN=…  node server.js

import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import pg from 'pg';

const contract = JSON.parse(readFileSync(new URL('./columns.json', import.meta.url), 'utf8'));
const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
const PORT = Number(process.env.PORT ?? 3014);
// Not a secret in any real sense — it ships inside the app binary and anyone who wants it can read
// it out. It is a doormat, not a lock: it stops a scanner writing rows into the dataset we make
// design decisions from. Real abuse means rotating it and shipping a build.
const TOKEN = process.env.SH_INGEST_TOKEN;
const MAX_BODY = 1_000_000;
const MAX_BATCH = 200;

// Routes are the tables, so a table declared in telemetry.toml is reachable the moment it exists and
// a route can never point at a table that does not.
const TABLES = Object.keys(contract.tables);

/** One INSERT per table, built once from the contract. */
const statements = Object.fromEntries(TABLES.map((table) => {
  const cols = contract.tables[table].columns;
  return [table, {
    cols,
    sql: (rows) => `INSERT INTO ${table} (${cols.map((c) => `"${c.name}"`).join(',')}) VALUES ` +
      rows.map((_, i) => '(' + cols.map((_, c) => `$${i * cols.length + c + 1}`).join(',') + ')').join(','),
  }];
}));

/**
 * One value, checked against the declaration rather than coerced into it.
 *
 * A missing required column is a rejected row, never a default: a default standing in for a
 * measurement is the failure this whole design is built against, and a row that silently reads
 * `synthetic = false` because the client forgot to say is worse than no row at all.
 */
function value(col, raw, where) {
  if (raw === undefined || raw === null) {
    if (col.required) throw new Error(`${where}: ${col.name} is required`);
    return null;
  }
  if (col.type === 'enum' && !col.values.includes(raw)) {
    throw new Error(`${where}: ${col.name} is not one of ${col.values.join('|')} (got ${JSON.stringify(raw)})`);
  }
  if (col.type === 'bool' && typeof raw !== 'boolean') throw new Error(`${where}: ${col.name} is not a boolean`);
  if ((col.type === 'int' || col.type === 'i64' || col.type === 'double') && typeof raw !== 'number') {
    throw new Error(`${where}: ${col.name} is not a number`);
  }
  if ((col.type === 'string' || col.type === 'uuid' || col.type === 'key') && typeof raw !== 'string') {
    throw new Error(`${where}: ${col.name} is not a string`);
  }
  return raw;
}

async function insert(table, batch) {
  if (!batch.length) return;
  const { cols, sql } = statements[table];
  const values = [];
  batch.forEach((row, i) => {
    for (const col of cols) values.push(value(col, row[col.name], `${table}[${i}]`));
  });
  await pool.query(sql(batch), values);
}

createServer((req, res) => {
  // /<table>, nothing else. No reads, no admin, no listing — this box's rule is that only Grafana is
  // public, and a collector is the deliberate exception, so it stays as small as the exception needs.
  const table = req.url.replace(/^\/+/, '').split(/[/?]/)[0];
  if (req.method !== 'POST' || !TABLES.includes(table)) {
    res.writeHead(404).end();
    return;
  }
  if (TOKEN && req.headers.authorization !== `Bearer ${TOKEN}`) {
    res.writeHead(401).end();
    return;
  }
  let body = '';
  let tooBig = false;
  req.on('data', (chunk) => {
    body += chunk;
    if (body.length > MAX_BODY) { tooBig = true; req.destroy(); }
  });
  req.on('end', async () => {
    if (tooBig) { res.writeHead(413).end(); return; }
    try {
      const parsed = JSON.parse(body);
      const batch = Array.isArray(parsed) ? parsed : [parsed];
      if (batch.length > MAX_BATCH) throw new Error(`batch of ${batch.length} exceeds ${MAX_BATCH}`);
      await insert(table, batch);
      res.writeHead(204).end();
    } catch (err) {
      // Logged and swallowed. The client never reads this, and a 500 it cannot see is not worth the
      // noise — but the message says which column and which row, because that is the one thing
      // worth knowing when a build starts being rejected.
      console.error(`${table} insert failed: ${err.message}`);
      res.writeHead(400).end();
    }
  });
}).listen(PORT, () => {
  console.log(`smash hockey collector on :${PORT} — tables: ${TABLES.join(', ')} (format ${contract.format})`);
});

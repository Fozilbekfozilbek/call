/**
 * debtSync.js
 *
 * Background job that keeps phone_numbers.debt in sync with an external
 * JSON endpoint every 5 seconds. The endpoint URL is stored in the
 * "settings" table under the key "debt_source_url" so it can be changed
 * at any time without restarting the server.
 *
 * Expected JSON format of the external endpoint:
 *   {
 *     "contracts": [
 *       { "contract_number": "SH-1024", "debt": 150000 },
 *       { "contract_number": "SH-1025", "debt":  75000 }
 *     ]
 *   }
 *
 * Only rows in phone_numbers that have a non-null contract_number AND
 * whose contract_number appears in the JSON are updated — all other rows
 * are left untouched. The "paid_amount" column is NOT cleared; the UI
 * shows the raw "debt" from the JSON as the canonical figure and no
 * longer lets workers enter manual payments (the external source is the
 * single source of truth for how much is owed).
 */

const pool = require('./db');

const INTERVAL_MS = 5000; // 5 seconds

let _running = false;

async function fetchUrl(url) {
  // Node 18+ has built-in fetch. For Node 16 we fall back to the
  // "node-fetch" package if available, otherwise bail gracefully.
  if (typeof fetch !== 'undefined') {
    const res = await fetch(url, { signal: AbortSignal.timeout(8000) });
    if (!res.ok) throw new Error(`HTTP ${res.status} — ${url}`);
    return res.json();
  }
  // node-fetch v2 (CommonJS)
  const nodeFetch = require('node-fetch');
  const res = await nodeFetch(url, { timeout: 8000 });
  if (!res.ok) throw new Error(`HTTP ${res.status} — ${url}`);
  return res.json();
}

async function syncOnce() {
  // 1. Read the URL from the DB (allows hot-change without server restart).
  const settingRow = await pool.query(
    "SELECT value FROM settings WHERE key = 'debt_source_url'"
  );
  const url = settingRow.rows[0]?.value?.trim();
  if (!url) return; // not configured yet — silent skip

  // 2. Fetch the external JSON.
  let data;
  try {
    data = await fetchUrl(url);
  } catch (err) {
    console.warn('[debtSync] fetch error:', err.message);
    return;
  }

  const contracts = data?.contracts;
  if (!Array.isArray(contracts) || contracts.length === 0) {
    console.warn('[debtSync] JSON\'da "contracts" massivi topilmadi yoki bo\'sh.');
    return;
  }

  // 3. Build a map: contractNumber -> debt
  const debtMap = new Map();
  for (const item of contracts) {
    const cn = String(item.contract_number ?? '').trim();
    const debt = Number(item.debt);
    if (cn && Number.isFinite(debt) && debt >= 0) {
      debtMap.set(cn, debt);
    }
  }
  if (debtMap.size === 0) return;

  // 4. Update phone_numbers rows whose contract_number matches.
  //    Do it in a single UPDATE using unnested arrays so it's one round-
  //    trip to the DB regardless of how many contracts are in the JSON.
  const contractNumbers = Array.from(debtMap.keys());
  const debtValues = contractNumbers.map((cn) => debtMap.get(cn));

  await pool.query(
    `UPDATE phone_numbers
     SET debt = v.debt::numeric
     FROM (
       SELECT unnest($1::text[]) AS contract_number,
              unnest($2::numeric[]) AS debt
     ) v
     WHERE phone_numbers.contract_number = v.contract_number`,
    [contractNumbers, debtValues]
  );
}

function start() {
  if (_running) return;
  _running = true;

  // Run immediately on startup, then every INTERVAL_MS.
  (async function loop() {
    while (_running) {
      try {
        await syncOnce();
      } catch (err) {
        console.error('[debtSync] unexpected error:', err.message);
      }
      await new Promise((resolve) => setTimeout(resolve, INTERVAL_MS));
    }
  })();

  console.log(`✅ debtSync started (interval: ${INTERVAL_MS / 1000}s)`);
}

function stop() {
  _running = false;
}

module.exports = { start, stop, syncOnce };

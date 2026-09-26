const pool = require('../config/db');
const { parsePhoneNumbersFromExcel } = require('../utils/excelParser');

// Accepts 'YYYY-MM-DD'. Falls back to today for anything missing/
// unparseable, e.g. a manual add with no date, or an Excel row whose
// "Sana" cell was empty.
function resolveEntryDate(value) {
  if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value.trim())) {
    return value.trim();
  }
  return new Date().toISOString().slice(0, 10);
}

// GET /admin/workers
// Stats: pending/called counts and total outstanding debt (from external
// JSON via debtSync — no paid_amount logic anymore).
async function listWorkers(req, res) {
  try {
    const result = await pool.query(
      `SELECT u.id, u.name, u.phone, u.created_at,
              COUNT(p.id) FILTER (WHERE p.call_count = 0)     AS pending_count,
              COUNT(p.id) FILTER (WHERE p.call_count > 0)     AS called_count,
              COALESCE(SUM(p.debt), 0)                        AS total_debt,
              COALESCE(SUM(CASE WHEN p.debt > 0 THEN p.debt ELSE 0 END), 0) AS total_outstanding
       FROM users u
       LEFT JOIN phone_numbers p ON p.worker_id = u.id
       WHERE u.role = 'worker'
       GROUP BY u.id
       ORDER BY u.name ASC`
    );
    res.json({ workers: result.rows });
  } catch (err) {
    console.error('listWorkers error:', err);
    res.status(500).json({ error: 'Serverda xatolik yuz berdi.' });
  }
}

// GET /admin/workers/:workerId/numbers
// Optional ?date=YYYY-MM-DD to only return entries added for that date.
async function getWorkerNumbers(req, res) {
  try {
    const { workerId } = req.params;
    const { date } = req.query;

    const params = [workerId];
    let dateFilter = '';
    if (typeof date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(date.trim())) {
      params.push(date.trim());
      dateFilter = ' AND entry_date = $2';
    }

    const result = await pool.query(
      `SELECT id, full_name, number, debt, paid_amount, contract_number, status, called_at, call_count, sort_order, created_at, entry_date
       FROM phone_numbers
       WHERE worker_id = $1${dateFilter}
       ORDER BY status ASC, sort_order ASC, created_at ASC`,
      params
    );
    res.json({ numbers: result.rows });
  } catch (err) {
    console.error('getWorkerNumbers error:', err);
    res.status(500).json({ error: 'Serverda xatolik yuz berdi.' });
  }
}

// GET /admin/workers/:workerId/numbers/:numberId/call-logs
// Full call history for one customer — every timestamp the worker called
// them, newest first. Lets admin see exactly how many times and when.
async function getNumberCallLogs(req, res) {
  try {
    const { workerId, numberId } = req.params;

    const owned = await pool.query(
      'SELECT id FROM phone_numbers WHERE id = $1 AND worker_id = $2',
      [numberId, workerId]
    );
    if (owned.rows.length === 0) {
      return res.status(404).json({ error: 'Raqam topilmadi.' });
    }

    const result = await pool.query(
      'SELECT id, called_at FROM call_logs WHERE phone_number_id = $1 ORDER BY called_at DESC',
      [numberId]
    );
    res.json({ logs: result.rows });
  } catch (err) {
    console.error('getNumberCallLogs error:', err);
    res.status(500).json({ error: 'Serverda xatolik yuz berdi.' });
  }
}

async function nextSortOrder(workerId) {
  const result = await pool.query(
    'SELECT COALESCE(MAX(sort_order), 0) AS max_order FROM phone_numbers WHERE worker_id = $1',
    [workerId]
  );
  return result.rows[0].max_order + 1;
}

function notifyWorker(workerId, count) {
  try {
    const { getIO } = require('../config/socket');
    getIO().to(`worker_${workerId}`).emit('numbersUploaded', {
      workerId: Number(workerId),
      count,
    });
  } catch (e) {
    console.warn('Socket emit failed (numbersUploaded):', e.message);
  }
}

// POST /admin/workers/:workerId/upload-excel
// multipart/form-data with a single field "file"
// Excel columns (in order): Ism, Familya, Telefon raqami, Qarzi, Sana.
// Each row's OWN date (column E) is used — if a row has no readable
// date, that row alone falls back to today, no date is asked for up
// front.
async function uploadExcel(req, res) {
  try {
    const { workerId } = req.params;

    const worker = await pool.query(
      "SELECT id FROM users WHERE id = $1 AND role = 'worker'",
      [workerId]
    );
    if (worker.rows.length === 0) {
      return res.status(404).json({ error: 'Ishchi topilmadi.' });
    }

    if (!req.file) {
      return res.status(400).json({ error: 'Excel fayl yuborilmadi.' });
    }

    const entries = await parsePhoneNumbersFromExcel(req.file.buffer);
    if (entries.length === 0) {
      return res.status(400).json({ error: 'Faylda birorta ham telefon raqam topilmadi.' });
    }

    let nextOrder = await nextSortOrder(workerId);

    const insertedNumbers = [];
    for (const entry of entries) {
      const rowDate = resolveEntryDate(entry.entryDate);
      const result = await pool.query(
        `INSERT INTO phone_numbers (worker_id, full_name, number, debt, status, sort_order, entry_date, contract_number)
         VALUES ($1, $2, $3, $4, 'pending', $5, $6, $7)
         RETURNING id, full_name, number, debt, paid_amount, contract_number, status, sort_order, created_at, entry_date`,
        [workerId, entry.fullName, entry.number, entry.debt, nextOrder, rowDate, entry.contractNumber || null]
      );
      insertedNumbers.push(result.rows[0]);
      nextOrder += 1;
    }

    notifyWorker(workerId, insertedNumbers.length);

    res.status(201).json({
      message: `${insertedNumbers.length} ta raqam muvaffaqiyatli yuklandi.`,
      numbers: insertedNumbers,
    });
  } catch (err) {
    console.error('uploadExcel error:', err);
    res.status(500).json({ error: err.message || 'Serverda xatolik yuz berdi.' });
  }
}

// POST /admin/workers/:workerId/numbers
// Manual single-entry add: { fullName?, number, debt?, entryDate?, contractNumber? }
async function addNumberManually(req, res) {
  try {
    const { workerId } = req.params;
    const { fullName, number, debt, entryDate, contractNumber } = req.body;

    if (!number || !String(number).trim()) {
      return res.status(400).json({ error: 'Telefon raqam majburiy.' });
    }

    const worker = await pool.query(
      "SELECT id FROM users WHERE id = $1 AND role = 'worker'",
      [workerId]
    );
    if (worker.rows.length === 0) {
      return res.status(404).json({ error: 'Ishchi topilmadi.' });
    }

    const nextOrder = await nextSortOrder(workerId);
    const debtValue = debt !== undefined && debt !== null && debt !== '' ? Number(debt) : 0;
    const resolvedDate = resolveEntryDate(entryDate);
    const contractNumberValue = contractNumber && String(contractNumber).trim() ? String(contractNumber).trim() : null;

    const result = await pool.query(
      `INSERT INTO phone_numbers (worker_id, full_name, number, debt, status, sort_order, entry_date, contract_number)
       VALUES ($1, $2, $3, $4, 'pending', $5, $6, $7)
       RETURNING id, full_name, number, debt, paid_amount, contract_number, status, sort_order, created_at, entry_date`,
      [workerId, fullName || null, String(number).trim(), Number.isFinite(debtValue) ? debtValue : 0, nextOrder, resolvedDate, contractNumberValue]
    );

    notifyWorker(workerId, 1);

    res.status(201).json({ message: 'Raqam qo\'shildi.', number: result.rows[0] });
  } catch (err) {
    console.error('addNumberManually error:', err);
    res.status(500).json({ error: 'Serverda xatolik yuz berdi.' });
  }
}

// GET /admin/settings/debt-source-url
// Returns the currently configured external JSON URL.
async function getDebtSourceUrl(req, res) {
  try {
    const result = await pool.query("SELECT value FROM settings WHERE key = 'debt_source_url'");
    res.json({ url: result.rows[0]?.value || '' });
  } catch (err) {
    console.error('getDebtSourceUrl error:', err);
    res.status(500).json({ error: 'Serverda xatolik yuz berdi.' });
  }
}

// PUT /admin/settings/debt-source-url
// body: { url: 'https://...' }
// Saves (or clears) the URL. The running sync loop picks it up within
// the next 5-second tick — no server restart required.
async function setDebtSourceUrl(req, res) {
  try {
    const { url } = req.body;
    const value = typeof url === 'string' ? url.trim() : '';

    await pool.query(
      "INSERT INTO settings (key, value) VALUES ('debt_source_url', $1) ON CONFLICT (key) DO UPDATE SET value = $1",
      [value]
    );

    // Trigger one immediate sync if a URL was provided.
    if (value) {
      const { syncOnce } = require('../config/debtSync');
      syncOnce().catch((e) => console.warn('[admin setDebtSourceUrl] syncOnce:', e.message));
    }

    res.json({ message: 'URL saqlandi.', url: value });
  } catch (err) {
    console.error('setDebtSourceUrl error:', err);
    res.status(500).json({ error: 'Serverda xatolik yuz berdi.' });
  }
}

module.exports = { listWorkers, getWorkerNumbers, getNumberCallLogs, uploadExcel, addNumberManually, getDebtSourceUrl, setDebtSourceUrl };

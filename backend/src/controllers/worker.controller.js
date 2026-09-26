const pool = require('../config/db');

// GET /worker/numbers
// Worker's own list — pending numbers first (in original order), called
// numbers pushed to the bottom (most recently called last). Optional
// ?date=YYYY-MM-DD to only return entries added for that date.
async function getMyNumbers(req, res) {
  try {
    const workerId = req.user.id;
    const { date } = req.query;

    const params = [workerId];
    let dateFilter = '';
    if (typeof date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(date.trim())) {
      params.push(date.trim());
      dateFilter = ' AND entry_date = $2';
    }

    const result = await pool.query(
      `SELECT id, full_name, number, debt, paid_amount, contract_number, status, called_at, call_count, sort_order, entry_date
       FROM phone_numbers
       WHERE worker_id = $1${dateFilter}
       ORDER BY
         CASE WHEN status = 'pending' THEN 0 ELSE 1 END,
         sort_order ASC,
         called_at ASC NULLS FIRST`,
      params
    );
    res.json({ numbers: result.rows });
  } catch (err) {
    console.error('getMyNumbers error:', err);
    res.status(500).json({ error: 'Serverda xatolik yuz berdi.' });
  }
}

// POST /worker/numbers/:id/mark-called
// Called by the Flutter app every time it detects a phone call to this
// customer was answered (see phone_state OFFHOOK handling on the
// client). A worker can call the same customer more than once — each
// call adds a row to call_logs (full history, exact time) and bumps
// call_count/called_at on the number itself (quick "latest" summary).
async function markCalled(req, res) {
  const client = await pool.connect();
  try {
    const workerId = req.user.id;
    const { id } = req.params;

    await client.query('BEGIN');

    const owned = await client.query(
      'SELECT id FROM phone_numbers WHERE id = $1 AND worker_id = $2 FOR UPDATE',
      [id, workerId]
    );
    if (owned.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Raqam topilmadi.' });
    }

    await client.query(
      'INSERT INTO call_logs (phone_number_id, worker_id) VALUES ($1, $2)',
      [id, workerId]
    );

    const result = await client.query(
      `UPDATE phone_numbers
       SET status = 'called', called_at = NOW(), call_count = call_count + 1
       WHERE id = $1 AND worker_id = $2
       RETURNING id, full_name, number, debt, paid_amount, contract_number, status, called_at, call_count`,
      [id, workerId]
    );

    await client.query('COMMIT');

    const updated = result.rows[0];

    // Real-time push to the admin dashboard.
    try {
      const { getIO } = require('../config/socket');
      getIO().to('admins').emit('numberCalled', {
        workerId: Number(workerId),
        number: updated,
      });
    } catch (e) {
      console.warn('Socket emit failed (numberCalled):', e.message);
    }

    res.json({ message: 'Holat yangilandi.', number: updated });
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('markCalled error:', err);
    res.status(500).json({ error: 'Serverda xatolik yuz berdi.' });
  } finally {
    client.release();
  }
}

// POST /worker/numbers/:id/collect-payment
// body: { amount }
// Adds "amount" to how much has been collected from this customer so
// far. Clamped so paid_amount never exceeds the original debt (no
// overpayment bookkeeping) — once it reaches the debt AND the customer
// has been called at least once, the Flutter app hides this entry from
// the active lists on its own.
async function collectPayment(req, res) {
  try {
    const workerId = req.user.id;
    const { id } = req.params;
    const { amount } = req.body;

    const amt = Number(amount);
    if (!Number.isFinite(amt) || amt <= 0) {
      return res.status(400).json({ error: 'To\'g\'ri summa kiriting.' });
    }

    const result = await pool.query(
      `UPDATE phone_numbers
       SET paid_amount = LEAST(debt, paid_amount + $1)
       WHERE id = $2 AND worker_id = $3
       RETURNING id, full_name, number, debt, paid_amount, contract_number, status, called_at, call_count, entry_date`,
      [amt, id, workerId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Raqam topilmadi.' });
    }

    const updated = result.rows[0];

    // Real-time push to the admin dashboard, mirroring markCalled above —
    // this is how the "yig'ilgan summa" stats stay live on the admin side.
    try {
      const { getIO } = require('../config/socket');
      getIO().to('admins').emit('paymentCollected', {
        workerId: Number(workerId),
        number: updated,
      });
    } catch (e) {
      console.warn('Socket emit failed (paymentCollected):', e.message);
    }

    res.json({ message: 'To\'lov saqlandi.', number: updated });
  } catch (err) {
    console.error('collectPayment error:', err);
    res.status(500).json({ error: 'Serverda xatolik yuz berdi.' });
  }
}

// POST /worker/numbers/:id/change-date
// body: { entryDate: 'YYYY-MM-DD' }
// Lets the worker themselves reassign which date this customer belongs
// to (e.g. they didn't get to call someone today and want to push them
// to tomorrow's list). The date filter on both the worker's and admin's
// screens is driven by this same entry_date, so it picks up the change
// automatically.
async function changeEntryDate(req, res) {
  try {
    const workerId = req.user.id;
    const { id } = req.params;
    const { entryDate } = req.body;

    if (typeof entryDate !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(entryDate.trim())) {
      return res.status(400).json({ error: 'Sana formati noto\'g\'ri (YYYY-MM-DD kerak).' });
    }

    const result = await pool.query(
      `UPDATE phone_numbers
       SET entry_date = $1
       WHERE id = $2 AND worker_id = $3
       RETURNING id, full_name, number, debt, paid_amount, contract_number, status, called_at, call_count, entry_date`,
      [entryDate.trim(), id, workerId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Raqam topilmadi.' });
    }

    res.json({ message: 'Sana yangilandi.', number: result.rows[0] });
  } catch (err) {
    console.error('changeEntryDate error:', err);
    res.status(500).json({ error: 'Serverda xatolik yuz berdi.' });
  }
}

module.exports = { getMyNumbers, markCalled, collectPayment, changeEntryDate };

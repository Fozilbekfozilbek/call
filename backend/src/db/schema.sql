-- Call Tracking App — PostgreSQL schema
-- Run this once against your database, e.g.:
--   psql -U postgres -d call_tracking -f src/db/schema.sql

CREATE TABLE IF NOT EXISTS users (
    id            SERIAL PRIMARY KEY,
    name          VARCHAR(255) NOT NULL,
    phone         VARCHAR(20)  NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role          VARCHAR(10)  NOT NULL CHECK (role IN ('admin', 'worker')),
    created_at    TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS phone_numbers (
    id          SERIAL PRIMARY KEY,
    worker_id   INTEGER      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    full_name   VARCHAR(255),
    number      VARCHAR(30)  NOT NULL,
    debt        NUMERIC(14, 2) NOT NULL DEFAULT 0,
    contract_number VARCHAR(100),
    status      VARCHAR(10)  NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'called')),
    called_at   TIMESTAMP,
    call_count  INTEGER      NOT NULL DEFAULT 0,
    sort_order  INTEGER      NOT NULL DEFAULT 0,
    created_at  TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- Every single call attempt (a worker can call the same customer more than
-- once — call_count/called_at on phone_numbers only track the latest
-- summary; this table keeps the full history so admin can see exactly how
-- many times and at what times each customer was called).
CREATE TABLE IF NOT EXISTS call_logs (
    id              SERIAL PRIMARY KEY,
    phone_number_id INTEGER NOT NULL REFERENCES phone_numbers(id) ON DELETE CASCADE,
    worker_id       INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    called_at       TIMESTAMP NOT NULL DEFAULT NOW()
);

-- If you already ran this schema before these columns existed, run instead:
--   ALTER TABLE phone_numbers ADD COLUMN IF NOT EXISTS full_name VARCHAR(255);
--   ALTER TABLE phone_numbers ADD COLUMN IF NOT EXISTS debt NUMERIC(14,2) NOT NULL DEFAULT 0;
--   ALTER TABLE phone_numbers ADD COLUMN IF NOT EXISTS entry_date DATE NOT NULL DEFAULT CURRENT_DATE;
--   ALTER TABLE phone_numbers ADD COLUMN IF NOT EXISTS paid_amount NUMERIC(14,2) NOT NULL DEFAULT 0;
--   ALTER TABLE phone_numbers ADD COLUMN IF NOT EXISTS contract_number VARCHAR(100);
--   ALTER TABLE phone_numbers ADD COLUMN IF NOT EXISTS call_count INTEGER NOT NULL DEFAULT 0;

-- Safe to re-run: adds the columns above to an already-existing table too.
ALTER TABLE phone_numbers ADD COLUMN IF NOT EXISTS full_name VARCHAR(255);
ALTER TABLE phone_numbers ADD COLUMN IF NOT EXISTS debt NUMERIC(14, 2) NOT NULL DEFAULT 0;
-- Date this entry belongs to (read from the Excel file itself, picked by
-- hand for a manual entry, or later changed by the worker themselves).
-- Defaults to "today" so old rows and any insert that forgets to send it
-- still get a sensible value.
ALTER TABLE phone_numbers ADD COLUMN IF NOT EXISTS entry_date DATE NOT NULL DEFAULT CURRENT_DATE;
-- Running total of how much of "debt" the worker has collected from this
-- customer so far. Remaining debt = debt - paid_amount (never negative —
-- the application clamps it). Once paid_amount reaches debt AND the
-- customer has been called at least once, the entry is hidden from both
-- the worker's and admin's active lists (it still counts in stats).
ALTER TABLE phone_numbers ADD COLUMN IF NOT EXISTS paid_amount NUMERIC(14, 2) NOT NULL DEFAULT 0;
-- Shartnoma raqami (contract number) — free text, optional, purely for
-- display/reference (not used in any lookup logic).
ALTER TABLE phone_numbers ADD COLUMN IF NOT EXISTS contract_number VARCHAR(100);
-- How many times this customer has been called in total. A worker can
-- call the same customer more than once; each call increments this and
-- adds a row to call_logs (see below) with the exact time.
ALTER TABLE phone_numbers ADD COLUMN IF NOT EXISTS call_count INTEGER NOT NULL DEFAULT 0;

-- System-wide settings (key-value pairs). Currently used to store the
-- URL of the external JSON endpoint that serves live debt amounts.
CREATE TABLE IF NOT EXISTS settings (
    key   VARCHAR(100) PRIMARY KEY,
    value TEXT
);

-- debt_source_url: URL to a JSON endpoint. Format the server expects:
--   { "contracts": [ { "contract_number": "SH-1024", "debt": 150000 }, ... ] }
-- The background sync job (started on server boot) fetches this URL every
-- 5 seconds and updates phone_numbers.debt for any row whose
-- contract_number matches. Rows with no contract_number are skipped.
-- Insert the URL once (e.g. via psql or the admin endpoint below); the
-- sync loop picks it up without a restart.
INSERT INTO settings (key, value) VALUES ('debt_source_url', '')
  ON CONFLICT (key) DO NOTHING;

CREATE INDEX IF NOT EXISTS idx_phone_numbers_worker_id ON phone_numbers(worker_id);
CREATE INDEX IF NOT EXISTS idx_phone_numbers_status ON phone_numbers(worker_id, status, sort_order);
CREATE INDEX IF NOT EXISTS idx_phone_numbers_entry_date ON phone_numbers(worker_id, entry_date);
CREATE INDEX IF NOT EXISTS idx_call_logs_phone_number_id ON call_logs(phone_number_id, called_at DESC);

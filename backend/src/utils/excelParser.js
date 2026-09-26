const ExcelJS = require('exceljs');

const phoneRegex = /^\+?[\d\s\-()]{7,20}$/;

function looksLikePhone(text) {
  if (!text) return false;
  const cleaned = String(text).trim().replace(/[\s\-()]/g, '');
  const digitsOnly = cleaned.replace(/^\+/, '');
  return phoneRegex.test(String(text).trim()) && /^\d{7,15}$/.test(digitsOnly);
}

function cleanPhone(text) {
  return String(text).trim().replace(/[\s\-()]/g, '');
}

function parseDebt(value) {
  if (value === null || value === undefined || value === '') return 0;
  const num = Number(String(value).replace(/[\s,]/g, ''));
  return Number.isFinite(num) ? num : 0;
}

/**
 * Parses whatever is in the "Sana" (date) column into 'YYYY-MM-DD', or
 * null if the cell is empty/unreadable (the caller then falls back to
 * today's date). Handles the three shapes ExcelJS can hand us:
 *   - a real JS Date (when the cell is formatted as a date in Excel)
 *   - a plain string like "23.09.2026", "23/09/2026" or "2026-09-23"
 *   - a raw Excel date serial number (rare, but happens with some exports)
 */
function parseEntryDate(value) {
  if (value === null || value === undefined || value === '') return null;

  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return value.toISOString().slice(0, 10);
  }

  const text = String(value).trim();
  if (!text) return null;

  // Already ISO: 2026-09-23
  let m = text.match(/^(\d{4})-(\d{1,2})-(\d{1,2})$/);
  if (m) {
    const [, y, mo, d] = m;
    return `${y}-${mo.padStart(2, '0')}-${d.padStart(2, '0')}`;
  }

  // dd.mm.yyyy or dd/mm/yyyy (the format most people type by hand in Uzbekistan)
  m = text.match(/^(\d{1,2})[.\/](\d{1,2})[.\/](\d{4})$/);
  if (m) {
    const [, d, mo, y] = m;
    return `${y}-${mo.padStart(2, '0')}-${d.padStart(2, '0')}`;
  }

  // Raw Excel serial date number (days since 1899-12-30), in case a cell
  // wasn't formatted as a date and ExcelJS handed us the number as text.
  if (/^\d+(\.\d+)?$/.test(text)) {
    const serial = Number(text);
    if (serial > 20000 && serial < 80000) {
      const excelEpoch = Date.UTC(1899, 11, 30);
      const d = new Date(excelEpoch + serial * 86400000);
      if (!Number.isNaN(d.getTime())) return d.toISOString().slice(0, 10);
    }
  }

  return null;
}

/**
 * Parses an uploaded Excel buffer into structured entries.
 *
 * Expected layout (one row per person), columns in this order:
 *   A: Ism (first name)
 *   B: Familya (last name)
 *   C: Telefon raqami (phone number)
 *   D: Qarzi (debt amount) — optional, defaults to 0
 *   E: Sana (date) — optional, defaults to today if empty/unreadable.
 *      Accepts an Excel date cell, or text like 23.09.2026 / 2026-09-23.
 *   F: Shartnoma raqami (contract number) — optional, free text.
 *
 * A header row (e.g. "Ism", "Familya", "Telefon", "Qarz", "Sana",
 * "Shartnoma") is detected and skipped automatically because it won't
 * contain a valid phone number in column C. For backward compatibility, a
 * sheet with phone numbers only (one number per row/column, no other
 * columns) is also supported — in that case every cell that looks like a
 * phone number is picked up with no name, zero debt, no date (defaults to
 * today) and no contract number, just like before.
 */
async function parsePhoneNumbersFromExcel(buffer) {
  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.load(buffer);

  const worksheet = workbook.worksheets[0];
  if (!worksheet) {
    throw new Error('Excel faylda hech qanday varaq topilmadi.');
  }

  const entries = [];
  const seenNumbers = new Set();

  worksheet.eachRow((row) => {
    const cells = row.values; // 1-indexed array, index 0 is unused
    const colA = cells[1] !== undefined && cells[1] !== null ? String(cells[1]).trim() : '';
    const colB = cells[2] !== undefined && cells[2] !== null ? String(cells[2]).trim() : '';
    const colC = cells[3] !== undefined && cells[3] !== null ? String(cells[3]).trim() : '';
    // colD (Qarzi/debt) is intentionally unused — debt no longer comes
    // from Excel, it is set by the external JSON sync.
    const colE = cells[5]; // Sana (date)
    const colF = cells[6] !== undefined && cells[6] !== null ? String(cells[6]).trim() : ''; // Shartnoma raqami

    // Structured layout: phone number expected in column C.
    if (looksLikePhone(colC)) {
      const number = cleanPhone(colC);
      if (!seenNumbers.has(number)) {
        seenNumbers.add(number);
        const fullNameParts = [colA, colB].filter((p) => p && !looksLikePhone(p));
        // Column layout (A=Ism, B=Familya, C=Telefon, D=Qarzi, E=Sana, F=Shartnoma).
        entries.push({
          fullName: fullNameParts.length > 0 ? fullNameParts.join(' ') : null,
          number,
          debt: 0,
          entryDate: parseEntryDate(colE),
          contractNumber: colF || null,
        });
      }
      return;
    }

    // Fallback: no structured columns detected on this row — scan every
    // cell for anything that looks like a bare phone number (old format:
    // just a list of numbers, no name/date/contract columns).
    row.eachCell((cell) => {
      const raw = cell.value;
      if (raw === null || raw === undefined) return;
      const text = String(raw).trim();
      if (!text || !looksLikePhone(text)) return;

      const number = cleanPhone(text);
      if (!seenNumbers.has(number)) {
        seenNumbers.add(number);
        entries.push({ fullName: null, number, debt: 0, entryDate: null, contractNumber: null });
      }
    });
  });

  return entries;
}

module.exports = { parsePhoneNumbersFromExcel };

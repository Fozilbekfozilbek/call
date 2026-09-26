const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const pool = require('../config/db');

function signToken(user) {
  return jwt.sign(
    { id: user.id, name: user.name, role: user.role },
    process.env.JWT_SECRET,
    { expiresIn: process.env.JWT_EXPIRES_IN || '30d' }
  );
}

// POST /auth/register
// Workers can self-register with just { name, phone, password }.
// To register an admin account, the request must also include
// { role: 'admin', adminSecret: '...' } matching ADMIN_REGISTRATION_SECRET.
async function register(req, res) {
  try {
    const { name, phone, password, role, adminSecret } = req.body;

    if (!name || !phone || !password) {
      return res.status(400).json({ error: 'Ism, telefon va parol majburiy.' });
    }

    let finalRole = 'worker';
    if (role === 'admin') {
      if (!adminSecret || adminSecret !== process.env.ADMIN_REGISTRATION_SECRET) {
        return res.status(403).json({ error: 'Admin sifatida ro\'yxatdan o\'tish uchun maxsus kod noto\'g\'ri.' });
      }
      finalRole = 'admin';
    }

    const existing = await pool.query('SELECT id FROM users WHERE phone = $1', [phone]);
    if (existing.rows.length > 0) {
      return res.status(409).json({ error: 'Bu telefon raqam allaqachon ro\'yxatdan o\'tgan.' });
    }

    const passwordHash = await bcrypt.hash(password, 10);

    const result = await pool.query(
      `INSERT INTO users (name, phone, password_hash, role)
       VALUES ($1, $2, $3, $4)
       RETURNING id, name, phone, role, created_at`,
      [name, phone, passwordHash, finalRole]
    );

    const user = result.rows[0];
    const token = signToken(user);

    res.status(201).json({ user, token });
  } catch (err) {
    console.error('register error:', err);
    res.status(500).json({ error: 'Serverda xatolik yuz berdi.' });
  }
}

// POST /auth/login
async function login(req, res) {
  try {
    const { phone, password } = req.body;
    if (!phone || !password) {
      return res.status(400).json({ error: 'Telefon va parol majburiy.' });
    }

    const result = await pool.query('SELECT * FROM users WHERE phone = $1', [phone]);
    const user = result.rows[0];

    if (!user) {
      return res.status(401).json({ error: 'Telefon yoki parol noto\'g\'ri.' });
    }

    const match = await bcrypt.compare(password, user.password_hash);
    if (!match) {
      return res.status(401).json({ error: 'Telefon yoki parol noto\'g\'ri.' });
    }

    const token = signToken(user);
    res.json({
      user: { id: user.id, name: user.name, phone: user.phone, role: user.role },
      token,
    });
  } catch (err) {
    console.error('login error:', err);
    res.status(500).json({ error: 'Serverda xatolik yuz berdi.' });
  }
}

module.exports = { register, login };

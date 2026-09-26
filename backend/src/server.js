require('dotenv').config();
const express = require('express');
const cors = require('cors');
const http = require('http');

const authRoutes = require('./routes/auth.routes');
const adminRoutes = require('./routes/admin.routes');
const workerRoutes = require('./routes/worker.routes');
const socketConfig = require('./config/socket');
const debtSync = require('./config/debtSync');

const app = express();
app.use(cors());
app.use(express.json());

app.get('/health', (req, res) => res.json({ status: 'ok' }));

app.use('/auth', authRoutes);
app.use('/admin', adminRoutes);
app.use('/worker', workerRoutes);

// Generic error handler (e.g. multer file-type errors)
app.use((err, req, res, next) => {
  console.error(err);
  res.status(err.status || 500).json({ error: err.message || 'Serverda xatolik yuz berdi.' });
});

const server = http.createServer(app);
socketConfig.init(server);

// Start the background debt-sync job (fetches external JSON every 5 s
// and updates phone_numbers.debt by contract_number).
debtSync.start();

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`🚀 Server ${PORT}-portda ishga tushdi`);
});

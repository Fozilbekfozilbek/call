const express = require('express');
const router = express.Router();
const { authenticate, requireRole } = require('../middleware/auth');
const upload = require('../middleware/upload');
const {
  listWorkers, getWorkerNumbers, getNumberCallLogs,
  uploadExcel, addNumberManually,
  getDebtSourceUrl, setDebtSourceUrl,
} = require('../controllers/admin.controller');

router.use(authenticate, requireRole('admin'));

router.get('/workers', listWorkers);
router.get('/workers/:workerId/numbers', getWorkerNumbers);
router.get('/workers/:workerId/numbers/:numberId/call-logs', getNumberCallLogs);
router.post('/workers/:workerId/upload-excel', upload.single('file'), uploadExcel);
router.post('/workers/:workerId/numbers', addNumberManually);

// Debt-source URL settings
router.get('/settings/debt-source-url', getDebtSourceUrl);
router.put('/settings/debt-source-url', setDebtSourceUrl);

module.exports = router;

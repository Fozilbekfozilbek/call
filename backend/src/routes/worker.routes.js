const express = require('express');
const router = express.Router();
const { authenticate, requireRole } = require('../middleware/auth');
const { getMyNumbers, markCalled, collectPayment, changeEntryDate } = require('../controllers/worker.controller');

router.use(authenticate, requireRole('worker'));

router.get('/numbers', getMyNumbers);
router.post('/numbers/:id/mark-called', markCalled);
router.post('/numbers/:id/collect-payment', collectPayment);
router.post('/numbers/:id/change-date', changeEntryDate);

module.exports = router;

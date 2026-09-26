const multer = require('multer');

// Keep the uploaded Excel file in memory; we parse it immediately and
// never need to persist the raw file to disk.
const storage = multer.memoryStorage();

const upload = multer({
  storage,
  limits: { fileSize: 10 * 1024 * 1024 }, // 10 MB max
  fileFilter: (req, file, cb) => {
    const okExt = /\.(xlsx|xls)$/i.test(file.originalname);
    if (!okExt) {
      return cb(new Error('Faqat .xlsx yoki .xls fayllarni yuklash mumkin.'));
    }
    cb(null, true);
  },
});

module.exports = upload;

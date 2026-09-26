# Call Tracking Backend

Node.js + Express + PostgreSQL + Socket.IO backend for the admin/worker
phone-call tracking app.

## O'rnatish

```bash
cd backend
npm install
cp .env.example .env
# .env faylni oching va DB_*, JWT_SECRET, ADMIN_REGISTRATION_SECRET qiymatlarini to'ldiring
```

## Baza yaratish

PostgreSQL'da bo'sh baza yarating (masalan `call_tracking`), so'ng:

```bash
npm run migrate
```

Bu `src/db/schema.sql` dagi jadvallarni (`users`, `phone_numbers`) yaratadi.

> Eski (avval o'rnatilgan) baza bilan ishlayotgan bo'lsangiz ham, kodni
> yangilagandan so'ng shu buyruqni qayta ishga tushiring — `entry_date`
> (sana) ustuni xavfsiz tarzda avtomatik qo'shiladi, mavjud ma'lumotlar
> o'chmaydi.

## Ishga tushirish

```bash
npm run dev     # nodemon bilan, development uchun
# yoki
npm start       # production uchun
```

Server `http://localhost:3000` da ishga tushadi (portni `.env` da o'zgartirish mumkin).

## API qisqacha

### Auth
- `POST /auth/register` — `{ name, phone, password }` → worker sifatida ro'yxatdan o'tadi.
  Admin sifatida ro'yxatdan o'tish uchun qo'shimcha `{ role: "admin", adminSecret: "..." }` yuboriladi (`.env` dagi `ADMIN_REGISTRATION_SECRET` bilan mos bo'lishi kerak).
- `POST /auth/login` — `{ phone, password }` → `{ user, token }`

Barcha keyingi so'rovlarda `Authorization: Bearer <token>` header talab qilinadi.

### Admin (rol: admin)
- `GET /admin/workers` — barcha ishchilar + statistikasi: `pending_count`, `called_count`, `collected_count` (pul olingan mijozlar soni), `total_collected` (jami yig'ilgan summa), `total_outstanding` (jami qolgan qarz)
- `GET /admin/workers/:workerId/numbers` — bitta ishchining to'liq raqamlar ro'yxati (ism, telefon, qarz, to'langan summa, shartnoma raqami, status, sana). Ixtiyoriy `?date=YYYY-MM-DD` — faqat shu sanaga tegishli yozuvlarni qaytaradi
- `POST /admin/workers/:workerId/upload-excel` — `multipart/form-data`, `file` maydoni. Sana so'ralmaydi — har bir qatorning sanasi Excel faylning "Sana" ustunidan (E) o'qiladi, bo'sh/noto'g'ri bo'lsa o'sha qatorga bugungi sana qo'yiladi
- `POST /admin/workers/:workerId/numbers` — qo'lda bitta raqam qo'shish: `{ fullName?, number, debt?, entryDate?, contractNumber? }` (`entryDate` `YYYY-MM-DD`, bo'lmasa bugungi sana)

### Worker (rol: worker)
- `GET /worker/numbers` — o'ziga tegishli raqamlar (pending birinchi, called oxirida). Ixtiyoriy `?date=YYYY-MM-DD` filter
- `POST /worker/numbers/:id/mark-called` — qo'ng'iroq javob berilgach chaqiriladi
- `POST /worker/numbers/:id/collect-payment` — `{ amount }` — mijozdan olingan summani yozib qo'yadi; `paid_amount`ga qo'shiladi, lekin `debt`dan oshib ketmaydi (avtomatik cheklanadi)

### Socket.IO real-vaqt eventlari
Ulanishdan so'ng darhol yuboring:
```js
socket.emit('identify', { role: 'admin' });               // admin uchun
socket.emit('identify', { role: 'worker', userId: 123 });  // worker uchun
```

- `numberCalled` — admin'ga yuboriladi, worker biror raqamni "called" qilganda: `{ workerId, number }`
- `paymentCollected` — admin'ga yuboriladi, worker to'lov yozganda: `{ workerId, number }`
- `numbersUploaded` — workerga yuboriladi, admin yangi raqamlar yuklaganda: `{ workerId, count }`

## Excel fayl formati

Endi Excel faylda 6 ta ustun qo'llab-quvvatlanadi (tartib muhim):

| A (Ism) | B (Familya) | C (Telefon raqami) | D (Qarzi) | E (Sana) | F (Shartnoma raqami) |
|---|---|---|---|---|---|
| Aziz | Karimov | +998901234567 | 150000 | 23.09.2026 | SH-1024 |
| Dilnoza | Yusupova | +998907654321 | 75000 | 2026-09-20 | SH-1025 |

- Sarlavha qatori (Ism, Familya, ...) bo'lsa ham, bo'lmasa ham — avtomatik aniqlanadi va o'tkazib yuboriladi (chunki C ustunida telefon raqam bo'lmaydi)
- **C ustuni** — telefon raqam bo'lishi shart, aks holda qator o'tkazib yuboriladi
- Ism, Familya, Qarzi, Sana va Shartnoma raqami — ixtiyoriy, bo'sh qoldirsa ham bo'ladi (Sana bo'sh bo'lsa, o'sha qatorga bugungi sana qo'yiladi)
- **E ustuni (Sana)** — Excelda sana formatida kiritilgan katak, yoki matn sifatida `23.09.2026`, `23/09/2026` yoki `2026-09-23` — barchasi tushuniladi
- **F ustuni (Shartnoma raqami)** — erkin matn, faqat ko'rsatish uchun (hisob-kitobda ishtirok etmaydi)
- Eski format (faqat bitta ustunga raqamlar, boshqa ustunlarsiz) ham hali ishlaydi — orqaga moslik saqlangan

Bundan tashqari, admin ilova ichidan **qo'lda** ham bitta-bitta raqam qo'sha oladi (`POST /admin/workers/:workerId/numbers` — `{ fullName, number, debt, entryDate, contractNumber }`), Excel shart emas — bu holatda sana admin tomonidan tanlanadi.

## To'lov yig'ish (qarzni yopish) va ro'yxatdan chiqish sharti

Worker o'z ekranida har bir mijoz kartasida kichik "Mijoz bergan summa" maydoniga pul miqdorini yozib, "Yozish" tugmasini bossa:
- O'sha summa mijozning `paid_amount`siga qo'shiladi (`debt`dan oshib ketmaydi)
- Qolgan qarz (`debt - paid_amount`) mijoz kartasida yangilanadi

Bir mijoz **faol ro'yxatdan** (ham worker, ham admin ekranida) chiqib ketishi uchun **ikkala shart ham** bajarilishi kerak:
1. Qarzi to'liq to'langan (qolgan qarz = 0)
2. Worker unga qo'ng'iroq qilgan (status = "called")

Agar shulardan faqat bittasi bajarilgan bo'lsa (masalan qarzi to'langan-u, hali qo'ng'iroq qilinmagan), mijoz **ataylab ro'yxatda qolaveradi** — shu bilan worker uni unutib qo'ymaydi va baribir qo'ng'iroq qilib, holatni yakunlaydi. Ikkalasi ham bajarilgach, mijoz:
- Worker ro'yxatidan yo'qoladi (admin yangi ro'yxat yuklamaguncha qaytib chiqmaydi)
- Admin ro'yxatidan ham yo'qoladi (tarix yo'qolmaydi — statistikaga (`called_count`, `collected_count`, `total_collected` va h.k.) hamon hisoblanadi, faqat faol ro'yxatdan chiqadi)

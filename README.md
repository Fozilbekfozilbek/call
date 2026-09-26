# Call Tracking — To'liq loyiha

Admin telefon raqamlarni Excel orqali ishchilarga yuklaydi, ishchi ro'yxatdan
raqamni bosib qo'ng'iroq qiladi, javob berilsa — admin darhol ko'radi va
ishchi tomonida raqam ro'yxat tagiga tushadi.

## Tarkib

```
backend/       Node.js + Express + PostgreSQL + Socket.IO (REST API + real-vaqt)
flutter_app/   Flutter (Android) — admin va worker uchun bitta ilova
```

## Ishga tushirish tartibi

1. **PostgreSQL** o'rnating va bo'sh baza yarating (`call_tracking`)
2. **Backend**: `backend/README.md` dagi qadamlar bo'yicha `.env` sozlang,
   `npm install`, `npm run migrate`, `npm run dev`
3. **Admin hisobi** yarating — `POST /auth/register` ga
   `{ name, phone, password, role: "admin", adminSecret: "<.env dagi ADMIN_REGISTRATION_SECRET>" }`
   yuborib (Postman yoki curl orqali), keyin shu login/parol bilan ilovaga kirasiz.
4. **Flutter**: `flutter_app/README.md` bo'yicha `setup.bat`ni ishga tushiring —
   u platforma fayllarini tayyorlaydi, paketlarni o'rnatadi va **tayyor
   release APK** yasab beradi.
5. Ishchilar ilova ichidan o'zlari ro'yxatdan o'tadi ("Ishchi sifatida
   ro'yxatdan o'tish" tugmasi) — ular darhol admin ro'yxatida ko'rinadi.
6. Admin ishchini tanlab, **Excel fayl yuklaydi** (Ism, Familya, Telefon
   raqami, Qarzi ustunlari bilan) **yoki qo'lda bitta-bitta raqam qo'shadi**
   → raqamlar ishchi kabinetida (ism va qarz bilan birga) paydo bo'ladi →
   ishchi bosib qo'ng'iroq qiladi → javob berilsa avtomatik ravishda admin
   tomonida "Qildi" statusiga o'tadi va ishchi ro'yxatida tagiga tushadi.

## Oqim diagrammasi

```
Admin login ──▶ Ishchilar ro'yxati ──▶ Ishchini tanlaydi ──▶ Excel yuklaydi
                                                                    │
                                                                    ▼
                                                    phone_numbers jadvaliga yoziladi
                                                                    │
                                            Socket.IO: "numbersUploaded" → workerga
                                                                    │
                                                                    ▼
Worker o'z kabinetida raqamlarni ko'radi ──▶ raqamga bosadi ──▶ ACTION_CALL orqali qo'ng'iroq
                                                                    │
                                              telefon holati kuzatiladi (OFFHOOK davomiyligi)
                                                                    │
                                                        Javob berildi deb aniqlansa:
                                                                    │
                                        POST /worker/numbers/:id/mark-called ──▶ DB yangilanadi
                                                                    │
                                              Socket.IO: "numberCalled" → barcha adminlarga
                                                                    │
                                    Admin ekranida "Qildi" hisoblagichi ortadi, ishchi
                                    ro'yxatida raqam pastga tushadi
```

## APK'ni bulutda (GitHub Actions) avtomatik qurish — Flutter kerak emas

Kompyuteringizda Flutter/Android SDK sozlash bilan ovora bo'lishni istamasangiz,
`.github/workflows/build-apk.yml` fayli buni siz uchun GitHub'ning bepul
serverlarida avtomatik qiladi:

1. github.com'da yangi (private bo'lsa ham bo'ladi) repozitoriy yarating
2. Shu loyihani o'sha repoga yuklang:
   ```bash
   cd call-tracking-project
   git init
   git add .
   git commit -m "Boshlang'ich versiya"
   git branch -M main
   git remote add origin https://github.com/<username>/<repo-nomi>.git
   git push -u origin main
   ```
3. GitHub'da repo sahifasida **Actions** bo'limiga o'ting — "Build Android APK"
   workflow avtomatik ishga tushadi (bir necha daqiqa davom etadi)
4. Tugagach, o'sha ishning sahifasida **Artifacts** bo'limidan
   `call-tracking-app-release` faylini yuklab oling — ichida `app-release.apk` bor

Kodga har safar o'zgartirish kiritib `git push` qilganingizda, yangi APK
avtomatik quriladi — mahalliy Flutter, Gradle, compileSdk muammolari haqida
umuman qayg'urish shart emas.



Qo'ng'iroq "javob berildimi yoki yo'qmi"ni avtomatik aniqlash — faqat
**Android**da ishlaydi (`READ_PHONE_STATE` ruxsati orqali). iOS buni
uchinchi tomon ilovalarga umuman ruxsat bermaydi, shuning uchun bu loyiha
faqat Android uchun mo'ljallangan (siz tanlagan variant).

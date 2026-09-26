# Call Tracking — Flutter App (Android)

Admin va worker (ishchi) rollari bitta ilova ichida, login paytida
serverdan kelgan `role` maydoniga qarab tegishli ekranga yo'naltiriladi.

## O'rnatish (avtomatik — bitta buyruq)

Bu papka Dart kodi (`lib/`), `pubspec.yaml` va bizning tayyor
`AndroidManifest.xml` shablonini o'z ichiga oladi. To'liq ishlaydigan
loyihaga aylantirish uchun **`setup.bat`** faylini shu papka ichida
ishga tushiring (ikki marta bosing yoki terminalda `setup.bat` deb yozing).

U avtomatik ravishda:
1. (faqat birinchi marta) Flutter platforma fayllarini (`android/`, gradle va h.k.) yaratadi — bizning `pubspec.yaml`, `lib/` va `AndroidManifest.xml`ni saqlab qoladi
2. `flutter pub get` bilan barcha paketlarni o'rnatadi
3. **Tayyor release APK yasaydi** — `build\app\outputs\flutter-apk\app-release.apk`

Skript tugagach, APK joylashgan papka avtomatik ochiladi — shu faylni
ishchilaringizga yuborsangiz, telefonlariga o'rnatib darhol ishlata oladi.

Qayta o'zgartirish kiritsangiz (masalan kod yangilansa), skriptni yana
ishga tushirishingiz kifoya — u android/ papkasini qayta yaratmaydi,
faqat yangi APK yasaydi.

Sinov uchun to'g'ridan-to'g'ri ulangan qurilmada ishga tushirish:
```bash
flutter devices        # ulangan qurilmani ko'rish
flutter run             # sinov uchun ishga tushirish
```

`lib/config/api_config.dart` faylida `baseUrl` allaqachon
`https://call.sofmebel.uz` bilan sozlangan — hech narsa o'zgartirish
shart emas.

## Muhim eslatmalar

### 1. Qo'ng'iroq holatini aniqlash (`phone_state` paketi)
`lib/services/call_service.dart` faylida qo'ng'iroq javob berilganini
aniqlash uchun OFFHOOK holatining davomiyligiga asoslangan evristika
ishlatilgan (3 soniyadan ko'p davom etsa — "javob berildi" deb hisoblanadi).
`phone_state` paketining aynan qaysi versiyasini ishlatayotganingizga qarab
status enum qiymatlari va event strukturasi biroz farq qilishi mumkin —
`flutter pub get` dan keyin paket hujjatini (`pub.dev/packages/phone_state`)
tekshirib, kerak bo'lsa `call_service.dart` dagi switch-case bandlarini
moslashtiring. Bu — ilovaning eng nozik joyi, chunki Android telefonlar
ishlab chiqaruvchilar bo'yicha turlicha xatti-harakat qilishi mumkin
(ba'zi qurilmalarda READ_CALL_LOG ham qo'shimcha kerak bo'lishi mumkin).

### 2. Runtime ruxsatlar
`CALL_PHONE` va `READ_PHONE_STATE` — "dangerous" toifadagi ruxsatlar.
Ilova birinchi marta qo'ng'iroq qilishga uringanda tizim ruxsat so'raydi
(`permission_handler` paketi orqali). Agar foydalanuvchi rad etsa, xato
xabari ko'rsatiladi — Sozlamalar orqali qo'lda yoqish kerak bo'ladi.

### 3. Google Play talablari
Agar ilovani Play Store'ga chiqarsangiz, `CALL_PHONE`/`READ_PHONE_STATE`
kabi ruxsatlar uchun **Permissions Declaration Form**ni to'ldirish va
ilovaning asosiy funksiyasi aynan shu ruxsatlarni talab qilishini
ko'rsatish kerak bo'ladi.

### 4. Ishlab chiqarishga tayyorlash
- `android:usesCleartextTraffic="true"` faqat development uchun (http://).
  Productionda backendni HTTPS orqali joylashtirib, bu qatorni olib tashlang.
- `ApiConfig.baseUrl`ni production serveringiz manziliga o'zgartiring.

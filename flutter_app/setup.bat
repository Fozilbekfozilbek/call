@echo off
setlocal enabledelayedexpansion
REM ============================================================
REM  Call Tracking App — to'liq avtomatik sozlash va APK yasash
REM  (Windows)
REM
REM  Bu skript:
REM    1) Flutter borligini tekshiradi
REM    2) (faqat birinchi marta) android/ va boshqa platforma
REM       fayllarini yaratadi, bizning kodimizni saqlab qoladi
REM    3) barcha kerakli paketlarni o'rnatadi
REM    4) tayyor release APK yasaydi
REM
REM  Ishlatish: shu papka (flutter_app) ichida ikki marta bosing
REM  yoki terminalda: setup.bat
REM  Qayta ishga tushirsangiz ham xavfsiz — allaqachon yaratilgan
REM  android/ papkasini qayta yaratmaydi, faqat yangilaydi.
REM ============================================================

echo [1/5] Flutter borligini tekshirish...
where flutter >nul 2>nul
if %errorlevel% neq 0 (
    echo XATO: Flutter topilmadi. Avval https://flutter.dev/docs/get-started/install saytidan
    echo Flutter SDK'ni o'rnating va PATH'ga qo'shing, keyin bu skriptni qayta ishga tushiring.
    pause
    exit /b 1
)

if exist "android\app" (
    echo [2/5] Platforma fayllari allaqachon mavjud — qayta yaratish o'tkazib yuborildi.
    copy /Y "android_manifest_template\AndroidManifest.xml" "android\app\src\main\AndroidManifest.xml" >nul
) else (
    echo [2/5] Platforma fayllarini birinchi marta yaratish ^(android/, gradle va h.k.^)...
    copy /Y "pubspec.yaml" "pubspec.yaml.bak" >nul
    xcopy /E /I /Y "lib" "lib_backup" >nul

    call flutter create --org com.sofmebel --project-name call_tracking_app .

    copy /Y "pubspec.yaml.bak" "pubspec.yaml" >nul
    xcopy /E /I /Y "lib_backup" "lib" >nul
    copy /Y "android_manifest_template\AndroidManifest.xml" "android\app\src\main\AndroidManifest.xml" >nul
    del "pubspec.yaml.bak" >nul
    rmdir /S /Q "lib_backup" >nul
)

echo [3/5] compileSdk versiyasini tekshirish va tuzatish (ba'zi paketlar SDK 36 talab qiladi)...
powershell -NoProfile -ExecutionPolicy Bypass -File "fix_compilesdk.ps1"
if %errorlevel% neq 0 (
    echo XATO: compileSdk tuzatishda muammo chiqdi. Yuqoridagi xabarni tekshiring.
    pause
    exit /b 1
)
echo Hozirgi compileSdk qatori:
if exist "android\app\build.gradle.kts" (
    findstr /C:"compileSdk" "android\app\build.gradle.kts"
) else (
    findstr /C:"compileSdk" "android\app\build.gradle"
)

echo [4/5] Paketlarni o'rnatish...
call flutter pub get
if %errorlevel% neq 0 (
    echo XATO: "flutter pub get" muvaffaqiyatsiz tugadi. Yuqoridagi xabarni tekshiring.
    pause
    exit /b 1
)

echo [5/5] Tayyor APK yasash ^(bu bir necha daqiqa vaqt olishi mumkin^)...
call flutter build apk --release
if %errorlevel% neq 0 (
    echo XATO: APK yasashda muammo chiqdi. Yuqoridagi xabarni tekshiring
    echo ^(ko'pincha "flutter doctor" bilan Android SDK/litsenziyalarni to'g'irlash yordam beradi^).
    pause
    exit /b 1
)

echo.
echo ============================================================
echo  TAYYOR! Ilovangiz shu yerda:
echo    build\app\outputs\flutter-apk\app-release.apk
echo.
echo  Shu faylni ishchilaringizga yuboring — telefoniga o'rnatib,
echo  darhol ishlatishi mumkin.
echo.
echo  Sinov uchun to'g'ridan-to'g'ri ulangan qurilmada ishga
echo  tushirmoqchi bo'lsangiz:
echo    flutter devices
echo    flutter run
echo ============================================================

explorer "build\app\outputs\flutter-apk"

pause

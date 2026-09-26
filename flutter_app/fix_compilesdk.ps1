# Makes sure EVERYTHING in this Android project compiles against SDK 36,
# because some plugins (file_picker -> flutter_plugin_android_lifecycle)
# now require it. Two separate things need patching, or the build fails
# even when it looks like it's already fixed:
#
#   1) android/app/build.gradle(.kts) — our own app module's compileSdk.
#      Easy: it's a single line, we just overwrite it with 36.
#
#   2) android/build.gradle(.kts) — the ROOT project. Every plugin
#      (file_picker, permission_handler, socket_io_client, ...) is its own
#      Gradle subproject and sets its OWN compileSdk internally via the
#      "flutter.compileSdkVersion" variable, which is a fixed value baked
#      into your installed Flutter SDK (often still 34 or 35) — patching
#      step 1 alone does NOT change that, which is exactly why the build
#      can still fail with something like:
#        ":file_picker is currently compiled against android-34"
#      even though android/app/build.gradle.kts already correctly shows
#      "compileSdk = 36". Step 2 forces every subproject to 36 as well,
#      after Gradle evaluates them, overriding whatever they set inside.
#
# Safe to run multiple times (idempotent on both files).

$kts = "android\app\build.gradle.kts"
$groovy = "android\app\build.gradle"

if (Test-Path $kts) {
    $path = $kts
} elseif (Test-Path $groovy) {
    $path = $groovy
} else {
    Write-Host "OGOHLANTIRISH: android/app/build.gradle(.kts) topilmadi, otkazib yuborildi."
    exit 0
}

$lines = Get-Content $path
$newLines = for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    if ($line -match '^(\s*compileSdk\s*=\s*).+$') {
        $matches[1] + "36"
    } elseif ($line -match '^(\s*compileSdkVersion\s+).+$') {
        $matches[1] + "36"
    } else {
        $line
    }
}
Set-Content -Path $path -Value $newLines
Write-Host "[1/2] compileSdk 36 ga sozlandi: $path"

# ---------------------------------------------------------------------
# Step 2: force every plugin subproject to compileSdk 36 too.
# ---------------------------------------------------------------------
$rootKts = "android\build.gradle.kts"
$rootGroovy = "android\build.gradle"
$marker = "// >>> fix_compilesdk.ps1: force compileSdk 36 on every plugin module"

if (Test-Path $rootKts) {
    $rootPath = $rootKts
    $block = @"


$marker
subprojects {
    afterEvaluate {
        extensions.findByType(com.android.build.gradle.BaseExtension::class.java)
            ?.compileSdkVersion(36)
    }
}
"@
} elseif (Test-Path $rootGroovy) {
    $rootPath = $rootGroovy
    $block = @"


$marker
subprojects {
    afterEvaluate { proj ->
        if (proj.hasProperty("android")) {
            proj.android.compileSdkVersion 36
        }
    }
}
"@
} else {
    Write-Host "OGOHLANTIRISH: android/build.gradle(.kts) (root) topilmadi — plagin compileSdk tuzatilmadi."
    exit 0
}

$rootContent = Get-Content -Raw $rootPath
if ($rootContent -notmatch [regex]::Escape($marker)) {
    Add-Content -Path $rootPath -Value $block
    Write-Host "[2/2] Barcha plagin modullari uchun compileSdk 36 majburlandi: $rootPath"
} else {
    Write-Host "[2/2] Plagin compileSdk tuzatishi allaqachon mavjud: $rootPath"
}

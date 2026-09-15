# =====================================================================
# SafeRise - Production Release Build (Windows PowerShell)
# Membangun APK release dengan dart-define dari scripts/build.config
# Pemakaian:
#   .\scripts\build-release.ps1              # build apk release
#   .\scripts\build-release.ps1 -Clean       # bersihkan dulu (flutter clean)
#   .\scripts\build-release.ps1 -Target appbundle
# =====================================================================
param(
    [switch]$Clean,
    [string]$Target = ""
)

$ErrorActionPreference = "Stop"

$configPath = Join-Path $PSScriptRoot "build.config"
if (-not (Test-Path $configPath)) {
    Copy-Item (Join-Path $PSScriptRoot "build.config.example") $configPath
    Write-Error "build.config belum ada -> sudah disalin dari build.config.example. ISI nilainya dulu, lalu jalankan ulang."
}

$config = @{}
Get-Content $configPath | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
        $idx = $line.IndexOf("=")
        $config[$line.Substring(0, $idx).Trim()] = $line.Substring($idx + 1).Trim()
    }
}

$mqttHost     = $config["MQTT_HOST"]
$mqttPort     = if ($config["MQTT_PORT"]) { $config["MQTT_PORT"] } else { "8883" }
$mqttUser     = $config["MQTT_USERNAME"]
$mqttPass     = $config["MQTT_PASSWORD"]
$backendUrl   = $config["BACKEND_URL"]
$flutterTarget = if ($Target -ne "") { $Target } elseif ($config["FLUTTER_TARGET"]) { $config["FLUTTER_TARGET"] } else { "apk" }

if (-not $mqttHost -or -not $backendUrl) {
    Write-Error "MQTT_HOST dan BACKEND_URL wajib diisi di build.config"
}

# Proyek Flutter berada satu folder di atas folder scripts/
$projectDir = Split-Path $PSScriptRoot -Parent
Push-Location $projectDir
try {
    if ($Clean) {
        Write-Host ">> flutter clean" -ForegroundColor Cyan
        flutter clean
        flutter pub get
    }

    $args = @(
        "build", $flutterTarget, "--release",
        "--dart-define=MQTT_HOST=$mqttHost",
        "--dart-define=MQTT_PORT=$mqttPort",
        "--dart-define=BACKEND_URL=$backendUrl"
    )
    if ($mqttUser) { $args += "--dart-define=MQTT_USERNAME=$mqttUser" }
    if ($mqttPass) { $args += "--dart-define=MQTT_PASSWORD=$mqttPass" }

    Write-Host ">> flutter $($args -join ' ')" -ForegroundColor Cyan
    flutter @args

    Write-Host ""
    Write-Host "✅ Build selesai." -ForegroundColor Green
    switch ($flutterTarget) {
        "apk"       { Write-Host "   APK : build\app\outputs\flutter-apk\app-release.apk" }
        "appbundle" { Write-Host "   AAB : build\app\outputs\bundle\release\app-release.aab" }
    }
} finally {
    Pop-Location
}

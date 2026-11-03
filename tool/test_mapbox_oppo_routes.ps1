$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

if (-not $env:MAPBOX_ACCESS_TOKEN -or -not $env:MAPBOX_ACCESS_TOKEN.StartsWith('pk.')) {
    throw 'Define MAPBOX_ACCESS_TOKEN with the public pk. token before running this test.'
}
if (-not $env:MAPBOX_DOWNLOADS_TOKEN) {
    throw 'Define MAPBOX_DOWNLOADS_TOKEN (Downloads:Read) before building the Android test.'
}

$devices = @(
    & adb devices |
        Select-Object -Skip 1 |
        Where-Object { $_ -match '^\S+\s+device$' } |
        ForEach-Object { ($_ -split '\s+')[0] }
)
if ($devices.Count -ne 1) {
    throw "Connect exactly one Android device with USB debugging enabled. Detected: $($devices.Count)"
}

$DeviceId = $devices[0]
$Brand = (& adb -s $DeviceId shell getprop ro.product.brand).Trim()
$Model = (& adb -s $DeviceId shell getprop ro.product.model).Trim()
if ($Brand -notmatch '^OPPO$') {
    throw "Expected a physical OPPO device; detected brand '$Brand', model '$Model'."
}

$OriginalWifiState = (& adb -s $DeviceId shell settings get global wifi_on).Trim()
$AirplaneModeEnabled = $false
$ReportDir = Join-Path $RepoRoot 'build'
New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
$ReportPath = Join-Path $ReportDir 'mapbox-oppo-route-validation.txt'
$DartDefineFile = Join-Path $env:TEMP ("espana-mapbox-" + [guid]::NewGuid().ToString() + ".json")
Start-Transcript -Path $ReportPath -Force | Out-Null

function Set-AirplaneMode([bool] $Enabled) {
    $action = if ($Enabled) { 'enable' } else { 'disable' }
    & adb -s $DeviceId shell cmd connectivity airplane-mode $action
    if ($LASTEXITCODE -ne 0) {
        $value = if ($Enabled) { '1' } else { '0' }
        $state = if ($Enabled) { 'true' } else { 'false' }
        & adb -s $DeviceId shell settings put global airplane_mode_on $value
        & adb -s $DeviceId shell am broadcast -a android.intent.action.AIRPLANE_MODE --ez state $state
    }
    $expected = if ($Enabled) { '1' } else { '0' }
    $actual = (& adb -s $DeviceId shell settings get global airplane_mode_on).Trim()
    if ($actual -ne $expected) {
        throw "Airplane mode verification failed. Expected $expected, received '$actual'."
    }
    if ($Enabled) {
        & adb -s $DeviceId shell svc wifi disable
        Start-Sleep -Seconds 3
        $wifi = (& adb -s $DeviceId shell settings get global wifi_on).Trim()
        if ($wifi -eq '1') {
            throw 'Wi-Fi is still enabled; refusing to claim an offline test.'
        }
    }
}

function Invoke-RouteIntegration([string] $Mode) {
    Write-Host "Running route phase '$Mode' on $Brand $Model ($DeviceId)."
    @{
        MAPBOX_ACCESS_TOKEN = $env:MAPBOX_ACCESS_TOKEN
        ROUTE_TEST_MODE = $Mode
    } | ConvertTo-Json -Compress | Set-Content -Path $DartDefineFile -Encoding ascii
    & flutter test -d $DeviceId "--dart-define-from-file=$DartDefineFile" 'integration_test/mapbox_android_live_route_test.dart'
    if ($LASTEXITCODE -ne 0) {
        throw "Mapbox integration phase '$Mode' failed with exit code $LASTEXITCODE."
    }
}

try {
    Write-Host "Physical Android device: $Brand $Model ($DeviceId)"
    Write-Host "Application package: com.espanaoutdoors.espana_outdoors"
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }

    Invoke-RouteIntegration 'online_and_download'

    $AirplaneModeEnabled = $true
    Set-AirplaneMode $true
    & adb -s $DeviceId shell am force-stop com.espanaoutdoors.espana_outdoors
    if ($LASTEXITCODE -ne 0) { throw 'Could not force-stop the app before the offline phase.' }

    Invoke-RouteIntegration 'offline'
    & adb -s $DeviceId logcat -d | Out-File -FilePath (Join-Path $ReportDir 'mapbox-oppo-logcat.txt') -Encoding utf8
    Write-Host "PASS: online route and new offline route validated on $Brand $Model."
    Write-Host "Report: $ReportPath"
}
finally {
    try {
        if ($AirplaneModeEnabled) {
            try {
                Set-AirplaneMode $false
            } catch {
                Write-Warning "Could not restore airplane mode through Android connectivity service; forcing radio settings back."
                & adb -s $DeviceId shell settings put global airplane_mode_on 0
                & adb -s $DeviceId shell am broadcast -a android.intent.action.AIRPLANE_MODE --ez state false
            }
        }
    } finally {
        try {
            if ($OriginalWifiState -eq '1') {
                & adb -s $DeviceId shell svc wifi enable
            } elseif ($OriginalWifiState -eq '0') {
                & adb -s $DeviceId shell svc wifi disable
            }
        } finally {
            if (Test-Path $DartDefineFile) { Remove-Item -Force $DartDefineFile }
            Stop-Transcript | Out-Null
        }
    }
}
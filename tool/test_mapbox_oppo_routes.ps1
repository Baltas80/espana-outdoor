$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot
$Adb = 'C:\Users\PAGREY\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$DeviceId = 'da09ac8c'
$PackageName = 'com.espanaoutdoors.espana_outdoors'
$ReportDir = Join-Path $RepoRoot 'build\mapbox-oppo-validation'
$ReportPath = Join-Path $ReportDir 'validation-report.txt'
$LogcatPath = Join-Path $ReportDir 'logcat.txt'
$DartDefineFile = Join-Path $env:TEMP ("espana-mapbox-" + [guid]::NewGuid().ToString() + '.json')
$Report = [System.Collections.Generic.List[string]]::new()

if (-not $env:MAPBOX_ACCESS_TOKEN -or -not $env:MAPBOX_ACCESS_TOKEN.StartsWith('pk.')) {
    throw 'Define MAPBOX_ACCESS_TOKEN with a public pk. token before running this test.'
}
if (-not $env:MAPBOX_DOWNLOADS_TOKEN) {
    throw 'Define MAPBOX_DOWNLOADS_TOKEN (Downloads:Read) before building the Android test.'
}
if (-not (Test-Path -LiteralPath $Adb)) { throw "ADB executable not found at the configured path: $Adb" }

New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
$OriginalAirplane = $null
$OriginalWifi = $null
$NetworkStateCaptured = $false
$OfflineConfirmed = $false
$Report.Add("Started: $(Get-Date -Format o)")
$Report.Add("Required device serial: $DeviceId")

function Invoke-Adb([string[]] $Arguments) {
    $output = & $Adb @Arguments
    if ($LASTEXITCODE -ne 0) { throw "ADB command failed: adb $($Arguments -join ' ') (exit $LASTEXITCODE)." }
    return ($output | Out-String).Trim()
}

function Set-AirplaneMode([bool] $Enabled) {
    $action = if ($Enabled) { 'enable' } else { 'disable' }
    & $Adb -s $DeviceId shell cmd connectivity airplane-mode $action | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $value = if ($Enabled) { '1' } else { '0' }
        $state = if ($Enabled) { 'true' } else { 'false' }
        Invoke-Adb @('-s', $DeviceId, 'shell', 'settings', 'put', 'global', 'airplane_mode_on', $value) | Out-Null
        Invoke-Adb @('-s', $DeviceId, 'shell', 'am', 'broadcast', '-a', 'android.intent.action.AIRPLANE_MODE', '--ez', 'state', $state) | Out-Null
    }
    $expected = if ($Enabled) { '1' } else { '0' }
    $actual = Invoke-Adb @('-s', $DeviceId, 'shell', 'settings', 'get', 'global', 'airplane_mode_on')
    if ($actual -ne $expected) { throw "Airplane mode verification failed; expected $expected, got '$actual'." }
}

function Invoke-RouteIntegration([string] $Mode) {
    $Report.Add("Phase started: $Mode at $(Get-Date -Format o)")
    @{ MAPBOX_ACCESS_TOKEN = $env:MAPBOX_ACCESS_TOKEN; ROUTE_TEST_MODE = $Mode } |
        ConvertTo-Json -Compress | Set-Content -LiteralPath $DartDefineFile -Encoding ascii
    $output = & flutter test -d $DeviceId "--dart-define-from-file=$DartDefineFile" 'integration_test/mapbox_android_live_route_test.dart' 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { $line = [string]$_; if ($line -notmatch 'MAPBOX_ACCESS_TOKEN|pk\.[A-Za-z0-9._-]+') { $Report.Add($line) } }
    if ($exitCode -ne 0) { throw "Mapbox integration phase '$Mode' failed with exit code $exitCode." }
    $source = if ($Mode -eq 'offline') { 'offline' } else { 'online' }
    if (-not ($output | ForEach-Object { [string]$_ } | Select-String -Quiet "MAPBOX_ROUTE_VALIDATION source=$source\b")) {
        throw "The '$Mode' phase completed without explicit '$source' route evidence."
    }
    $Report.Add("Phase passed: $Mode; explicit route origin=$source")
}

try {
    $deviceList = Invoke-Adb @('devices', '-l')
    $authorized = $deviceList -split "`r?`n" | Where-Object { $_ -match '^da09ac8c\s+device\b' }
    if (-not $authorized) { throw "Required OPPO $DeviceId is not authorized and online. No substitute device will be accepted.`n$deviceList" }
    $state = Invoke-Adb @('-s', $DeviceId, 'get-state')
    if ($state -ne 'device') { throw "Required device $DeviceId is not ready; state='$state'." }
    $OriginalAirplane = Invoke-Adb @('-s', $DeviceId, 'shell', 'settings', 'get', 'global', 'airplane_mode_on')
    $OriginalWifi = Invoke-Adb @('-s', $DeviceId, 'shell', 'settings', 'get', 'global', 'wifi_on')
    if ($OriginalAirplane -notin @('0','1') -or $OriginalWifi -notin @('0','1')) { throw 'Could not determine original connectivity states.' }
    $NetworkStateCaptured = $true
    $brand = Invoke-Adb @('-s', $DeviceId, 'shell', 'getprop', 'ro.product.brand')
    $model = Invoke-Adb @('-s', $DeviceId, 'shell', 'getprop', 'ro.product.model')
    if ($brand -ne 'OPPO' -or $model -ne 'CPH2009') { throw "Expected OPPO CPH2009; detected $brand $model." }
    $Report.Add("Device verified: $brand $model ($DeviceId)")
    $Report.Add("Original connectivity: airplane=$OriginalAirplane wifi=$OriginalWifi")

    & flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }
    Invoke-RouteIntegration 'online_and_download'

    Set-AirplaneMode $true
    Invoke-Adb @('-s', $DeviceId, 'shell', 'svc', 'wifi', 'disable') | Out-Null
    Start-Sleep -Seconds 3
    $wifi = Invoke-Adb @('-s', $DeviceId, 'shell', 'settings', 'get', 'global', 'wifi_on')
    if ($wifi -ne '0') { throw "Wi-Fi is still enabled (wifi_on=$wifi); offline test refused." }
    Invoke-Adb @('-s', $DeviceId, 'shell', 'am', 'force-stop', $PackageName) | Out-Null
    Invoke-RouteIntegration 'offline'
    $airplaneNow = Invoke-Adb @('-s', $DeviceId, 'shell', 'settings', 'get', 'global', 'airplane_mode_on')
    $wifiNow = Invoke-Adb @('-s', $DeviceId, 'shell', 'settings', 'get', 'global', 'wifi_on')
    if ($airplaneNow -ne '1' -or $wifiNow -ne '0') { throw 'Connectivity changed during the offline route request.' }
    $OfflineConfirmed = $true
    $Report.Add("PASS: fresh native offline route confirmed at $(Get-Date -Format o)")
}
catch {
    $Report.Add("FAIL: $($_.Exception.Message)")
    throw
}
finally {
    if (Test-Path -LiteralPath $Adb) {
        try { & $Adb -s $DeviceId logcat -d | Out-File -LiteralPath $LogcatPath -Encoding utf8 } catch { $Report.Add("Logcat collection failed: $($_.Exception.Message)") }
    }
    if ($NetworkStateCaptured) {
        try { Set-AirplaneMode ($OriginalAirplane -eq '1') } catch { $Report.Add("Airplane mode restore failed: $($_.Exception.Message)") }
        try {
            $wifiAction = if ($OriginalWifi -eq '1') { 'enable' } else { 'disable' }
            & $Adb -s $DeviceId shell svc wifi $wifiAction | Out-Null
        } catch { $Report.Add("Wi-Fi restore failed: $($_.Exception.Message)") }
    }
    if (-not $OfflineConfirmed) { $Report.Add('RESULT: FAIL (offline route origin was not confirmed)') }
    $Report.Add("Finished: $(Get-Date -Format o)")
    $Report | Set-Content -LiteralPath $ReportPath -Encoding utf8
    if (Test-Path -LiteralPath $DartDefineFile) { Remove-Item -LiteralPath $DartDefineFile -Force }
}

if (-not $OfflineConfirmed) { throw 'Validation cannot pass without explicit native OFFLINE route confirmation.' }
Write-Host "PASS: online route and fresh native offline route validated on OPPO CPH2009 ($DeviceId)."
Write-Host "Report: $ReportPath"
Write-Host "Logcat: $LogcatPath"

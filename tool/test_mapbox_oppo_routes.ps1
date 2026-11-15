param([switch]$RebootAfterOffline)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot
$AdbCommand = if ($env:ADB) { $env:ADB } else { (Get-Command adb -ErrorAction SilentlyContinue).Source }
if (-not $AdbCommand) { throw 'ADB was not found. Add platform-tools to PATH or set ADB.' }
$Adb = $AdbCommand
$DeviceId = if ($env:ANDROID_SERIAL) { $env:ANDROID_SERIAL } else { 'da09ac8c' }
$ExpectedModel = if ($env:EXPECTED_ANDROID_MODEL) { $env:EXPECTED_ANDROID_MODEL } else { 'CPH2009' }
$PackageName = if ($env:ANDROID_APPLICATION_ID) { $env:ANDROID_APPLICATION_ID } else { 'com.espanaoutdoors.espana_outdoors' }
$OfflineRegionId = 'espana-outdoor-cordoba-poc'
$GradleFile = Join-Path $RepoRoot 'android\app\build.gradle.kts'
$GradleText = Get-Content -LiteralPath $GradleFile -Raw
if ($GradleText -notmatch '(?m)^\s*namespace\s*=\s*"([^"]+)"') {
    throw 'Could not resolve the Flutter integration-test package from the Android Gradle namespace.'
}
$TestPackageName = $Matches[1]
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
$SourceCommit = (& git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $SourceCommit.Length -ne 40 -or $SourceCommit -notmatch '^[0-9a-f]+$') {
    throw 'Could not resolve the exact source commit for the physical validation report.'
}
$Report.Add("Source commit: $SourceCommit")
$Report.Add("Application ID: $PackageName")
$Report.Add("Integration namespace: $TestPackageName")

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
    $output = & flutter test --no-pub --reporter expanded -d $DeviceId "--dart-define-from-file=$DartDefineFile" 'integration_test/mapbox_android_live_route_test.dart' 2>&1
    $exitCode = $LASTEXITCODE
    $outputLines = @($output | ForEach-Object { [string]$_ })
    $outputLines | ForEach-Object {
        $line = [string]$_
        if ($line -notmatch 'MAPBOX_ACCESS_TOKEN|pk\.[A-Za-z0-9._-]+') { $Report.Add($line) }
    }
    if ($exitCode -ne 0) { throw "Mapbox integration phase '$Mode' failed with exit code $exitCode." }
    $source = if ($Mode -eq 'offline') { 'offline' } else { 'online' }
    if (-not ($outputLines | Select-String -Quiet "MAPBOX_ROUTE_VALIDATION source=$source\b")) {
        throw "The '$Mode' phase completed without explicit '$source' route evidence."
    }
    if ($Mode -eq 'offline') {
        # MAPBOX_OFFLINE_MAP_RENDERED is emitted by the CI host PNG validator,
        # not the Dart integration test. Validate the native MapWidget callbacks.
        $diagnostics = $outputLines |
            Where-Object { $_ -match 'MAPBOX_OFFLINE_MAP_DIAGNOSTICS' } |
            Select-Object -Last 1
        if (-not $diagnostics) {
            throw 'The offline phase did not emit native Mapbox render diagnostics.'
        }
        foreach ($marker in @('style_loaded=true','map_loaded=true','full_frame=true','idle=true','load_errors=0','resource_failures=0')) {
            if ($diagnostics -notmatch [regex]::Escape($marker)) {
                throw "Offline Mapbox render diagnostics did not satisfy '$marker'."
            }
        }
        if ($diagnostics -notmatch 'rendered_frames=[1-9][0-9]*') {
            throw 'Offline Mapbox did not report a completed render frame.'
        }
        $Report.Add($diagnostics)
    }
    $Report.Add("Phase passed: $Mode; explicit route origin=$source")
}
function Assert-OfflineRegionPersisted {
    $preferences = Invoke-Adb @('-s', $DeviceId, 'shell', 'run-as', $PackageName, 'cat', 'shared_prefs/espana_outdoor_offline.xml')
    $markerName = 'offline:' + $OfflineRegionId
    if ($preferences -notmatch [regex]::Escape($markerName) -or $preferences -notmatch 'value="true"') {
        throw "Offline region completion marker is missing from app-private SharedPreferences: $OfflineRegionId."
    }
    $tileStoreFile = Invoke-Adb @('-s', $DeviceId, 'shell', 'run-as', $PackageName, 'sh', '-c', 'find no_backup/mapbox-tiles -type f | head -n 1')
    if ([string]::IsNullOrWhiteSpace($tileStoreFile)) {
        throw "No persisted Mapbox TileStore file was found for region $OfflineRegionId."
    }
    $Report.Add("MAPBOX_TILESTORE_FILES_PRESENT region=$OfflineRegionId marker=true")
}

try {
    $deviceList = Invoke-Adb @('devices', '-l')
    $devicePattern = '^' + [regex]::Escape($DeviceId) + '\s+device\b'
    $authorized = $deviceList -split "`r?`n" | Where-Object { $_ -match $devicePattern }
    if (-not $authorized) { throw "Required OPPO $DeviceId is not authorized and online. No substitute device will be accepted.`n$deviceList" }
    $state = Invoke-Adb @('-s', $DeviceId, 'get-state')
    if ($state -ne 'device') { throw "Required device $DeviceId is not ready; state='$state'." }
    $OriginalAirplane = Invoke-Adb @('-s', $DeviceId, 'shell', 'settings', 'get', 'global', 'airplane_mode_on')
    $OriginalWifi = Invoke-Adb @('-s', $DeviceId, 'shell', 'settings', 'get', 'global', 'wifi_on')
    if ($OriginalAirplane -notin @('0','1') -or $OriginalWifi -notin @('0','1')) { throw 'Could not determine original connectivity states.' }
    $NetworkStateCaptured = $true
    $brand = Invoke-Adb @('-s', $DeviceId, 'shell', 'getprop', 'ro.product.brand')
    $model = Invoke-Adb @('-s', $DeviceId, 'shell', 'getprop', 'ro.product.model')
    if ($brand -ne 'OPPO' -or $model -ne $ExpectedModel) { throw "Expected OPPO $ExpectedModel; detected $brand $model." }
    $Report.Add("Device verified: $brand $model ($DeviceId)")
    $Report.Add("Original connectivity: airplane=$OriginalAirplane wifi=$OriginalWifi")

    & flutter pub get --enforce-lockfile
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get --enforce-lockfile failed.' }
    $pythonCommand = if ($env:PYTHON) { $env:PYTHON } elseif (Get-Command python -ErrorAction SilentlyContinue) { (Get-Command python).Source } elseif (Get-Command py -ErrorAction SilentlyContinue) { (Get-Command py).Source } else { $null }
    if (-not $pythonCommand) { throw 'Python 3 is required for the Mapbox compatibility patch checks.' }
    if ((Split-Path -Leaf $pythonCommand) -eq 'py.exe') {
        & $pythonCommand -3 tool/test_patch_mapbox_resource_expiry.py
        if ($LASTEXITCODE -ne 0) { throw 'Mapbox resource-expiry patch tests failed.' }
        & $pythonCommand -3 tool/patch_mapbox_resource_expiry.py
        if ($LASTEXITCODE -ne 0) { throw 'Mapbox resource-expiry patch failed.' }
        & $pythonCommand -3 tool/verify_mapbox_lock.py
    } else {
        & $pythonCommand tool/test_patch_mapbox_resource_expiry.py
        if ($LASTEXITCODE -ne 0) { throw 'Mapbox resource-expiry patch tests failed.' }
        & $pythonCommand tool/patch_mapbox_resource_expiry.py
        if ($LASTEXITCODE -ne 0) { throw 'Mapbox resource-expiry patch failed.' }
        & $pythonCommand tool/verify_mapbox_lock.py
    }
    if ($LASTEXITCODE -ne 0) { throw 'Mapbox lockfile verification failed.' }
    Invoke-RouteIntegration 'online_and_download'

    Set-AirplaneMode $true
    Invoke-Adb @('-s', $DeviceId, 'shell', 'svc', 'wifi', 'disable') | Out-Null
    Start-Sleep -Seconds 3
    $wifi = Invoke-Adb @('-s', $DeviceId, 'shell', 'settings', 'get', 'global', 'wifi_on')
    if ($wifi -ne '0') { throw "Wi-Fi is still enabled (wifi_on=$wifi); offline test refused." }
    # Flutter installs the integration-test runner under Gradle's namespace,
    # which is intentionally different from the staging/production application ID.
    $ProcessPackages = @($TestPackageName, $PackageName) | Select-Object -Unique
    foreach ($package in $ProcessPackages) {
        Invoke-Adb @('-s', $DeviceId, 'shell', 'am', 'force-stop', $package) | Out-Null
    }
    Start-Sleep -Seconds 2
    foreach ($package in $ProcessPackages) {
        $processOutput = & $Adb -s $DeviceId shell pidof $package 2>$null
        $processExitCode = $LASTEXITCODE
        if ($processExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace(($processOutput | Out-String).Trim())) {
            throw "Integration process '$package' survived force-stop; offline relaunch refused."
        }
        if ($processExitCode -gt 1) {
            throw "Could not verify that integration process '$package' stopped (adb exit $processExitCode)."
        }
    }
    $Report.Add("Stopped integration-test namespace package '$TestPackageName' and app package '$PackageName' before offline phase.")
    Invoke-RouteIntegration 'offline'
    $airplaneNow = Invoke-Adb @('-s', $DeviceId, 'shell', 'settings', 'get', 'global', 'airplane_mode_on')
    $wifiNow = Invoke-Adb @('-s', $DeviceId, 'shell', 'settings', 'get', 'global', 'wifi_on')
    if ($airplaneNow -ne '1' -or $wifiNow -ne '0') { throw 'Connectivity changed during the offline route request.' }
    Assert-OfflineRegionPersisted

    if ($RebootAfterOffline) {
        $Report.Add("Reboot persistence validation started at $(Get-Date -Format o)")
        Invoke-Adb @('-s', $DeviceId, 'reboot') | Out-Null
        Invoke-Adb @('-s', $DeviceId, 'wait-for-device') | Out-Null
        $bootDeadline = (Get-Date).AddMinutes(3)
        $bootComplete = ''
        while ((Get-Date) -lt $bootDeadline) {
            try {
                $bootComplete = Invoke-Adb @('-s', $DeviceId, 'shell', 'getprop', 'sys.boot_completed')
                if ($bootComplete -eq '1') { break }
            } catch { }
            Start-Sleep -Seconds 3
        }
        if ($bootComplete -ne '1') { throw 'OPPO did not finish booting within three minutes.' }

        Set-AirplaneMode $true
        Invoke-Adb @('-s', $DeviceId, 'shell', 'svc', 'wifi', 'disable') | Out-Null
        Start-Sleep -Seconds 3
        $airplaneAfterBoot = Invoke-Adb @('-s', $DeviceId, 'shell', 'settings', 'get', 'global', 'airplane_mode_on')
        $wifiAfterBoot = Invoke-Adb @('-s', $DeviceId, 'shell', 'settings', 'get', 'global', 'wifi_on')
        if ($airplaneAfterBoot -ne '1' -or $wifiAfterBoot -ne '0') {
            throw 'Could not re-establish and verify airplane mode after reboot.'
        }
        Invoke-Adb @('-s', $DeviceId, 'shell', 'am', 'force-stop', $PackageName) | Out-Null
        Invoke-RouteIntegration 'offline'
        Assert-OfflineRegionPersisted
        $Report.Add("PASS: offline TileStore and routing persisted after device reboot at $(Get-Date -Format o)")
    }

    $OfflineConfirmed = $true
    $Report.Add("PASS: fresh native offline route confirmed at $(Get-Date -Format o)")
}
catch {
    $Report.Add("FAIL: $($_.Exception.Message)")
    throw
}
finally {
    if (Test-Path -LiteralPath $Adb) {
        try {
            $logcat = Invoke-Adb @('-s', $DeviceId, 'logcat', '-d')
            if ($env:MAPBOX_ACCESS_TOKEN) { $logcat = $logcat.Replace($env:MAPBOX_ACCESS_TOKEN, '[REDACTED]') }
            $logcat = [regex]::Replace($logcat, '(?i)(access_token=)[^&\s]+', '$1[REDACTED]')
            $logcat | Out-File -LiteralPath $LogcatPath -Encoding utf8
        } catch { $Report.Add("Logcat collection failed: $($_.Exception.Message)") }
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
Write-Host "PASS: online route and fresh native offline route validated on OPPO $ExpectedModel ($DeviceId)."
Write-Host "Report: $ReportPath"
Write-Host "Logcat: $LogcatPath"

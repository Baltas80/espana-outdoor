param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseApkPath,

    [Parameter(Mandatory = $true)]
    [string]$ValidationManifestPath,

    [switch]$RebootAfterOffline
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot
$AdbCommand = if ($env:ADB) { $env:ADB } else { (Get-Command adb -ErrorAction SilentlyContinue).Source }
if (-not $AdbCommand) { throw 'ADB was not found. Add platform-tools to PATH or set ADB.' }
$Adb = $AdbCommand
$DeviceId = if ($env:ANDROID_SERIAL) { $env:ANDROID_SERIAL } else { 'da09ac8c' }
$ExpectedModel = if ($env:EXPECTED_ANDROID_MODEL) { $env:EXPECTED_ANDROID_MODEL } else { 'CPH2009' }
$ReleaseApkPath = (Resolve-Path -LiteralPath $ReleaseApkPath).Path
$ValidationManifestPath = (Resolve-Path -LiteralPath $ValidationManifestPath).Path
$Manifest = @{}
Get-Content -LiteralPath $ValidationManifestPath | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)
$LogcatPath = Join-Path $ReportDir 'logcat.txt'
$DartDefineFile = Join-Path $env:TEMP ("espana-mapbox-" + [guid]::NewGuid().ToString() + '.json')
$Report = [System.Collections.Generic.List[string]]::new()

if (-not $env:MAPBOX_ACCESS_TOKEN -or -not $env:MAPBOX_ACCESS_TOKEN.StartsWith('pk.')) {
    throw 'Define MAPBOX_ACCESS_TOKEN with a public pk. token before running this test.'
}
if (-not $env:MAPBOX_DOWNLOADS_TOKEN) {
    throw 'Define MAPBOX_DOWNLOADS_TOKEN (Downloads:Read) before building the Android test.'
}
$env:ANDROID_APPLICATION_ID = $PackageName
$env:ANDROID_SERIAL = $DeviceId
if (-not (Test-Path -LiteralPath $Adb)) { throw "ADB executable not found at the configured path: $Adb" }

New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
$OriginalAirplane = $null
$OriginalWifi = $null
$NetworkStateCaptured = $false
$OfflineConfirmed = $false
$Report.Add("Started: $(Get-Date -Format o)")
$Report.Add("Required device serial: $DeviceId")
$Report.Add("Release APK: $ReleaseApkPath")
$Report.Add("Release APK SHA-256: $ActualApkSha256")
$Report.Add("Release APK package/versionCode: $PackageName/$ExpectedVersionCode")
$Report.Add("Artifact source commit: $SourceCommit")

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

function Invoke-ReleaseOfflineSmoke([string] $Phase) {
    $Report.Add("Release APK offline smoke started: $Phase at $(Get-Date -Format o)")
    Invoke-Adb @('-s', $DeviceId, 'logcat', '-c') | Out-Null
    Invoke-Adb @('-s', $DeviceId, 'shell', 'am', 'force-stop', $PackageName) | Out-Null
    Invoke-Adb @('-s', $DeviceId, 'shell', 'monkey', '-p', $PackageName, '1') | Out-Null
    Start-Sleep -Seconds 10
    $pid = Invoke-Adb @('-s', $DeviceId, 'shell', 'pidof', $PackageName)
    if (-not $pid) { throw "Release APK process did not remain alive during $Phase offline smoke." }

    $remoteXml = '/sdcard/espana-outdoor-release-window.xml'
    Invoke-Adb @('-s', $DeviceId, 'shell', 'uiautomator', 'dump', $remoteXml) | Out-Null
    $xmlText = Invoke-Adb @('-s', $DeviceId, 'shell', 'cat', $remoteXml)
    if ($xmlText -match 'No se pudo cargar el mapa|Reintentar') {
        throw "Release APK displayed the Mapbox loader error during $Phase offline smoke."
    }
    [xml]$document = $xmlText
    $mapNode = $document.SelectSingleNode("//node[@text='Mapa' or @content-desc='Mapa']")
    if (-not $mapNode) { throw "Release APK did not expose the Mapa destination during $Phase offline smoke." }
    $bounds = [regex]::Match($mapNode.GetAttribute('bounds'), '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]
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
    if ($Mode -eq 'offline' -and -not ($output | ForEach-Object { [string]$_ } | Select-String -Quiet 'MAPBOX_OFFLINE_MAP_RENDERED')) {
        throw 'The offline phase did not confirm Mapbox map rendering from the downloaded TileStore.'
    }
    $Report.Add("Phase passed: $Mode; explicit route origin=$source")
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

    Invoke-Adb @('-s', $DeviceId, 'install', '-r', $ReleaseApkPath) | Out-Null
    $installedPath = Invoke-Adb @('-s', $DeviceId, 'shell', 'pm', 'path', $PackageName)
    if ($installedPath -notmatch [regex]::Escape($PackageName)) {
        throw "The exact release APK did not install as $PackageName."
    }
    $installedDump = Invoke-Adb @('-s', $DeviceId, 'shell', 'dumpsys', 'package', $PackageName)
    if ($installedDump -notmatch "versionCode=$ExpectedVersionCode\\b") {
        throw "Installed package versionCode does not match the CI manifest ($ExpectedVersionCode)."
    }
    $Report.Add("PASS: exact release APK installed; sha256=$ActualApkSha256")

    & flutter pub get --enforce-lockfile
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get --enforce-lockfile failed.' }
    $python = if (Get-Command python -ErrorAction SilentlyContinue) { (Get-Command python).Source } elseif (Get-Command py -ErrorAction SilentlyContinue) { (Get-Command py).Source } else { $null }
    if (-not $python) { throw 'Python 3 is required for the Mapbox compatibility patch checks.' }
    if ((Split-Path -Leaf $python) -eq 'py.exe') {
        & $python -3 tool/test_patch_mapbox_resource_expiry.py
        if ($LASTEXITCODE -ne 0) { throw 'Mapbox resource-expiry patch tests failed.' }
        & $python -3 tool/patch_mapbox_resource_expiry.py
        if ($LASTEXITCODE -ne 0) { throw 'Mapbox resource-expiry patch failed.' }
        & $python -3 tool/verify_mapbox_lock.py
    } else {
        & $python tool/test_patch_mapbox_resource_expiry.py
        if ($LASTEXITCODE -ne 0) { throw 'Mapbox resource-expiry patch tests failed.' }
        & $python tool/patch_mapbox_resource_expiry.py
        if ($LASTEXITCODE -ne 0) { throw 'Mapbox resource-expiry patch failed.' }
        & $python tool/verify_mapbox_lock.py
    }
    if ($LASTEXITCODE -ne 0) { throw 'Mapbox lockfile verification failed.' }
    Invoke-RouteIntegration 'online_and_download'

    Set-AirplaneMode $true
    Invoke-Adb @('-s', $DeviceId, 'shell', 'svc', 'wifi', 'disable') | Out-Null
    Start-Sleep -Seconds 3
    $wifi = Invoke-Adb @('-s', $DeviceId, 'shell', 'settings', 'get', 'global', 'wifi_on')
    if ($wifi -ne '0') { throw "Wi-Fi is still enabled (wifi_on=$wifi); offline test refused." }
    Invoke-Adb @('-s', $DeviceId, 'shell', 'am', 'force-stop', $PackageName) | Out-Null
    Invoke-RouteIntegration 'offline'
    # Reinstall the exact release-mode APK after the debug integration test.
    # The update must preserve the downloaded TileStore; a signing mismatch
    # fails closed rather than uninstalling and erasing the region.
    Invoke-Adb @('-s', $DeviceId, 'install', '-r', $ReleaseApkPath) | Out-Null
    $Report.Add('PASS: exact release APK reinstalled over the integration test app without uninstalling app data.')
    Invoke-ReleaseOfflineSmoke 'post-integration'
    $airplaneNow = Invoke-Adb @('-s', $DeviceId, 'shell', 'settings', 'get', 'global', 'airplane_mode_on')
    $wifiNow = Invoke-Adb @('-s', $DeviceId, 'shell', 'settings', 'get', 'global', 'wifi_on')
    if ($airplaneNow -ne '1' -or $wifiNow -ne '0') { throw 'Connectivity changed during the offline route request.' }

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
        Invoke-Adb @('-s', $DeviceId, 'install', '-r', $ReleaseApkPath) | Out-Null
        Invoke-ReleaseOfflineSmoke 'post-reboot'
        $Report.Add("PASS: offline TileStore persisted after reboot; exact release APK relaunched offline at $(Get-Date -Format o)")
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
) { $Manifest[$matches[1]] = $matches[2] }
}
$RequiredManifestKeys = @(
    'apk_sha256',
    'application_id',
    'version_code',
    'source_commit',
    'mapbox_runtime_token',
    'mapbox_downloads_token',
    'validation_scope'
)
foreach ($key in $RequiredManifestKeys) {
    if (-not $Manifest.ContainsKey($key) -or -not $Manifest[$key]) {
        throw "Android validation manifest is missing required field '$key'."
    }
}
if ($Manifest['mapbox_runtime_token'] -ne 'available' -or
    $Manifest['mapbox_downloads_token'] -ne 'available' -or
    $Manifest['validation_scope'] -ne 'runtime-capable-artifact') {
    throw 'The selected artifact was not built with both Mapbox credentials and runtime validation scope.'
}
$ActualApkSha256 = (Get-FileHash -LiteralPath $ReleaseApkPath -Algorithm SHA256).Hash.ToLowerInvariant()
$ExpectedApkSha256 = $Manifest['apk_sha256'].ToLowerInvariant()
if ($ActualApkSha256 -ne $ExpectedApkSha256) {
    throw "APK SHA-256 mismatch. Expected $ExpectedApkSha256; got $ActualApkSha256."
}
$ExpectedPackageName = $Manifest['application_id']
$ExpectedVersionCode = $Manifest['version_code']
$SourceCommit = $Manifest['source_commit']
$CurrentSourceCommit = (& git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $CurrentSourceCommit -ne $SourceCommit) {
    throw "Checkout commit does not match the artifact source commit. Expected $SourceCommit; got $CurrentSourceCommit."
}
if ($env:ANDROID_APPLICATION_ID -and $env:ANDROID_APPLICATION_ID -ne $ExpectedPackageName) {
    throw "ANDROID_APPLICATION_ID '$env:ANDROID_APPLICATION_ID' does not match APK package '$ExpectedPackageName'."
}
$PackageName = $ExpectedPackageName
$SdkRoot = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { $null }
if (-not $SdkRoot) { throw 'Set ANDROID_SDK_ROOT or ANDROID_HOME to verify the APK package/version.' }
$AaptCandidates = Get-ChildItem -Path (Join-Path $SdkRoot 'build-tools') -Filter 'aapt.exe' -Recurse -File -ErrorAction SilentlyContinue
$Aapt = $AaptCandidates | Sort-Object { [version]$_.Directory.Name } -Descending | Select-Object -First 1
if (-not $Aapt) { throw 'Android build-tools aapt.exe was not found.' }
$Badging = & $Aapt.FullName dump badging $ReleaseApkPath 2>&1
if ($LASTEXITCODE -ne 0) { throw "aapt could not inspect APK: $($Badging | Out-String)" }
$BadgingText = $Badging -join "`n"
$PackageMatch = [regex]::Match($BadgingText, "package: name='([^']+)' versionCode='([^']+)'")
if (-not $PackageMatch.Success) { throw 'Could not read application ID/versionCode from the APK manifest.' }
if ($PackageMatch.Groups[1].Value -ne $ExpectedPackageName -or
    $PackageMatch.Groups[2].Value -ne $ExpectedVersionCode) {
    throw "APK package/version mismatch. Manifest expects $ExpectedPackageName/$ExpectedVersionCode; APK is $($PackageMatch.Groups[1].Value)/$($PackageMatch.Groups[2].Value)."
}
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
    if ($Mode -eq 'offline' -and -not ($output | ForEach-Object { [string]$_ } | Select-String -Quiet 'MAPBOX_OFFLINE_MAP_RENDERED')) {
        throw 'The offline phase did not confirm Mapbox map rendering from the downloaded TileStore.'
    }
    $Report.Add("Phase passed: $Mode; explicit route origin=$source")
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
)
    if (-not $bounds.Success) { throw 'Could not determine the Mapa destination tap bounds.' }
    $tapX = [int](($bounds.Groups[1].Value | ForEach-Object { [int]$_ }) + ([int]$bounds.Groups[3].Value - [int]$bounds.Groups[1].Value) / 2)
    $tapY = [int](([int]$bounds.Groups[2].Value + [int]$bounds.Groups[4].Value) / 2)
    Invoke-Adb @('-s', $DeviceId, 'shell', 'input', 'tap', "$tapX", "$tapY") | Out-Null
    Start-Sleep -Seconds 15

    $postXml = Invoke-Adb @('-s', $DeviceId, 'shell', 'uiautomator', 'dump', $remoteXml) | Out-Null
    $postText = Invoke-Adb @('-s', $DeviceId, 'shell', 'cat', $remoteXml)
    if ($postText -match 'No se pudo cargar el mapa|Reintentar') {
        throw "Release APK displayed the Mapbox loader error after opening Mapa during $Phase offline smoke."
    }
    $logcat = Invoke-Adb @('-s', $DeviceId, 'logcat', '-d')
    if ($logcat -match 'FATAL EXCEPTION|Fatal signal [0-9]+ \((SIGSEGV|SIGABRT)\)|Abort message:|backtrace:') {
        throw "Release APK crashed during $Phase offline smoke."
    }
    $remoteScreenshot = '/sdcard/espana-outdoor-release-offline.png'
    $localScreenshot = Join-Path $ReportDir ("release-offline-" + $Phase + ".png")
    Invoke-Adb @('-s', $DeviceId, 'shell', 'screencap', '-p', $remoteScreenshot) | Out-Null
    Invoke-Adb @('-s', $DeviceId, 'pull', $remoteScreenshot, $localScreenshot) | Out-Null
    if (-not (Test-Path -LiteralPath $localScreenshot) -or (Get-Item -LiteralPath $localScreenshot).Length -lt 1024) {
        throw 'Release APK offline screenshot was not captured.'
    }
    $Report.Add("PASS: exact release APK relaunched and opened Mapa offline ($Phase); screenshot=$localScreenshot")
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
    if ($Mode -eq 'offline' -and -not ($output | ForEach-Object { [string]$_ } | Select-String -Quiet 'MAPBOX_OFFLINE_MAP_RENDERED')) {
        throw 'The offline phase did not confirm Mapbox map rendering from the downloaded TileStore.'
    }
    $Report.Add("Phase passed: $Mode; explicit route origin=$source")
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

    Invoke-Adb @('-s', $DeviceId, 'install', '-r', $ReleaseApkPath) | Out-Null
    $installedPath = Invoke-Adb @('-s', $DeviceId, 'shell', 'pm', 'path', $PackageName)
    if ($installedPath -notmatch [regex]::Escape($PackageName)) {
        throw "The exact release APK did not install as $PackageName."
    }
    $installedDump = Invoke-Adb @('-s', $DeviceId, 'shell', 'dumpsys', 'package', $PackageName)
    if ($installedDump -notmatch "versionCode=$ExpectedVersionCode\\b") {
        throw "Installed package versionCode does not match the CI manifest ($ExpectedVersionCode)."
    }
    $Report.Add("PASS: exact release APK installed; sha256=$ActualApkSha256")

    & flutter pub get --enforce-lockfile
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get --enforce-lockfile failed.' }
    $python = if (Get-Command python -ErrorAction SilentlyContinue) { (Get-Command python).Source } elseif (Get-Command py -ErrorAction SilentlyContinue) { (Get-Command py).Source } else { $null }
    if (-not $python) { throw 'Python 3 is required for the Mapbox compatibility patch checks.' }
    if ((Split-Path -Leaf $python) -eq 'py.exe') {
        & $python -3 tool/test_patch_mapbox_resource_expiry.py
        if ($LASTEXITCODE -ne 0) { throw 'Mapbox resource-expiry patch tests failed.' }
        & $python -3 tool/patch_mapbox_resource_expiry.py
        if ($LASTEXITCODE -ne 0) { throw 'Mapbox resource-expiry patch failed.' }
        & $python -3 tool/verify_mapbox_lock.py
    } else {
        & $python tool/test_patch_mapbox_resource_expiry.py
        if ($LASTEXITCODE -ne 0) { throw 'Mapbox resource-expiry patch tests failed.' }
        & $python tool/patch_mapbox_resource_expiry.py
        if ($LASTEXITCODE -ne 0) { throw 'Mapbox resource-expiry patch failed.' }
        & $python tool/verify_mapbox_lock.py
    }
    if ($LASTEXITCODE -ne 0) { throw 'Mapbox lockfile verification failed.' }
    Invoke-RouteIntegration 'online_and_download'

    Set-AirplaneMode $true
    Invoke-Adb @('-s', $DeviceId, 'shell', 'svc', 'wifi', 'disable') | Out-Null
    Start-Sleep -Seconds 3
    $wifi = Invoke-Adb @('-s', $DeviceId, 'shell', 'settings', 'get', 'global', 'wifi_on')
    if ($wifi -ne '0') { throw "Wi-Fi is still enabled (wifi_on=$wifi); offline test refused." }
    Invoke-Adb @('-s', $DeviceId, 'shell', 'am', 'force-stop', $PackageName) | Out-Null
    Invoke-RouteIntegration 'offline'
    # Reinstall the exact release-mode APK after the debug integration test.
    # The update must preserve the downloaded TileStore; a signing mismatch
    # fails closed rather than uninstalling and erasing the region.
    Invoke-Adb @('-s', $DeviceId, 'install', '-r', $ReleaseApkPath) | Out-Null
    $Report.Add('PASS: exact release APK reinstalled over the integration test app without uninstalling app data.')
    Invoke-ReleaseOfflineSmoke 'post-integration'
    $airplaneNow = Invoke-Adb @('-s', $DeviceId, 'shell', 'settings', 'get', 'global', 'airplane_mode_on')
    $wifiNow = Invoke-Adb @('-s', $DeviceId, 'shell', 'settings', 'get', 'global', 'wifi_on')
    if ($airplaneNow -ne '1' -or $wifiNow -ne '0') { throw 'Connectivity changed during the offline route request.' }

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
        Invoke-Adb @('-s', $DeviceId, 'install', '-r', $ReleaseApkPath) | Out-Null
        Invoke-ReleaseOfflineSmoke 'post-reboot'
        $Report.Add("PASS: offline TileStore persisted after reboot; exact release APK relaunched offline at $(Get-Date -Format o)")
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
) { $Manifest[$matches[1]] = $matches[2] }
}
$RequiredManifestKeys = @(
    'apk_sha256',
    'application_id',
    'version_code',
    'source_commit',
    'mapbox_runtime_token',
    'mapbox_downloads_token',
    'validation_scope'
)
foreach ($key in $RequiredManifestKeys) {
    if (-not $Manifest.ContainsKey($key) -or -not $Manifest[$key]) {
        throw "Android validation manifest is missing required field '$key'."
    }
}
if ($Manifest['mapbox_runtime_token'] -ne 'available' -or
    $Manifest['mapbox_downloads_token'] -ne 'available' -or
    $Manifest['validation_scope'] -ne 'runtime-capable-artifact') {
    throw 'The selected artifact was not built with both Mapbox credentials and runtime validation scope.'
}
$ActualApkSha256 = (Get-FileHash -LiteralPath $ReleaseApkPath -Algorithm SHA256).Hash.ToLowerInvariant()
$ExpectedApkSha256 = $Manifest['apk_sha256'].ToLowerInvariant()
if ($ActualApkSha256 -ne $ExpectedApkSha256) {
    throw "APK SHA-256 mismatch. Expected $ExpectedApkSha256; got $ActualApkSha256."
}
$ExpectedPackageName = $Manifest['application_id']
$ExpectedVersionCode = $Manifest['version_code']
$SourceCommit = $Manifest['source_commit']
$CurrentSourceCommit = (& git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $CurrentSourceCommit -ne $SourceCommit) {
    throw "Checkout commit does not match the artifact source commit. Expected $SourceCommit; got $CurrentSourceCommit."
}
if ($env:ANDROID_APPLICATION_ID -and $env:ANDROID_APPLICATION_ID -ne $ExpectedPackageName) {
    throw "ANDROID_APPLICATION_ID '$env:ANDROID_APPLICATION_ID' does not match APK package '$ExpectedPackageName'."
}
$PackageName = $ExpectedPackageName
$SdkRoot = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { $null }
if (-not $SdkRoot) { throw 'Set ANDROID_SDK_ROOT or ANDROID_HOME to verify the APK package/version.' }
$AaptCandidates = Get-ChildItem -Path (Join-Path $SdkRoot 'build-tools') -Filter 'aapt.exe' -Recurse -File -ErrorAction SilentlyContinue
$Aapt = $AaptCandidates | Sort-Object { [version]$_.Directory.Name } -Descending | Select-Object -First 1
if (-not $Aapt) { throw 'Android build-tools aapt.exe was not found.' }
$Badging = & $Aapt.FullName dump badging $ReleaseApkPath 2>&1
if ($LASTEXITCODE -ne 0) { throw "aapt could not inspect APK: $($Badging | Out-String)" }
$BadgingText = $Badging -join "`n"
$PackageMatch = [regex]::Match($BadgingText, "package: name='([^']+)' versionCode='([^']+)'")
if (-not $PackageMatch.Success) { throw 'Could not read application ID/versionCode from the APK manifest.' }
if ($PackageMatch.Groups[1].Value -ne $ExpectedPackageName -or
    $PackageMatch.Groups[2].Value -ne $ExpectedVersionCode) {
    throw "APK package/version mismatch. Manifest expects $ExpectedPackageName/$ExpectedVersionCode; APK is $($PackageMatch.Groups[1].Value)/$($PackageMatch.Groups[2].Value)."
}
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
    if ($Mode -eq 'offline' -and -not ($output | ForEach-Object { [string]$_ } | Select-String -Quiet 'MAPBOX_OFFLINE_MAP_RENDERED')) {
        throw 'The offline phase did not confirm Mapbox map rendering from the downloaded TileStore.'
    }
    $Report.Add("Phase passed: $Mode; explicit route origin=$source")
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
) { $Manifest[$matches[1]] = $matches[2] }
}
$RequiredManifestKeys = @('apk_sha256', 'application_id', 'version_code', 'source_commit', 'mapbox_runtime_token', 'mapbox_downloads_token', 'validation_scope')
foreach ($key in $RequiredManifestKeys) {
    if (-not $Manifest.ContainsKey($key) -or -not $Manifest[$key]) { throw "Android validation manifest is missing required field '$key'." }
}
if ($Manifest['mapbox_runtime_token'] -ne 'available' -or $Manifest['mapbox_downloads_token'] -ne 'available' -or $Manifest['validation_scope'] -ne 'runtime-capable-artifact') {
    throw 'The selected artifact was not built with both Mapbox credentials and runtime validation scope.'
}
$ActualApkSha256 = (Get-FileHash -LiteralPath $ReleaseApkPath -Algorithm SHA256).Hash.ToLowerInvariant()
$ExpectedApkSha256 = $Manifest['apk_sha256'].ToLowerInvariant()
if ($ActualApkSha256 -ne $ExpectedApkSha256) { throw "APK SHA-256 mismatch. Expected $ExpectedApkSha256; got $ActualApkSha256." }
$ExpectedPackageName = $Manifest['application_id']
$ExpectedVersionCode = $Manifest['version_code']
$SourceCommit = $Manifest['source_commit']
$CurrentSourceCommit = (& git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $CurrentSourceCommit -ne $SourceCommit) { throw "Checkout commit does not match artifact source commit. Expected $SourceCommit; got $CurrentSourceCommit." }
if ($env:ANDROID_APPLICATION_ID -and $env:ANDROID_APPLICATION_ID -ne $ExpectedPackageName) { throw "ANDROID_APPLICATION_ID '$env:ANDROID_APPLICATION_ID' does not match APK package '$ExpectedPackageName'." }
$PackageName = $ExpectedPackageName
$SdkRoot = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { $null }
if (-not $SdkRoot) { throw 'Set ANDROID_SDK_ROOT or ANDROID_HOME to verify APK package/version.' }
$AaptCandidates = Get-ChildItem -Path (Join-Path $SdkRoot 'build-tools') -Filter 'aapt.exe' -Recurse -File -ErrorAction SilentlyContinue
$Aapt = $AaptCandidates | Sort-Object { [version]$_.Directory.Name } -Descending | Select-Object -First 1
if (-not $Aapt) { throw 'Android build-tools aapt.exe was not found.' }
$Badging = & $Aapt.FullName dump badging $ReleaseApkPath 2>&1
if ($LASTEXITCODE -ne 0) { throw "aapt could not inspect APK: $($Badging | Out-String)" }
$BadgingText = $Badging -join "`n"
$PackageMatch = [regex]::Match($BadgingText, "package: name='([^']+)' versionCode='([^']+)'")
if (-not $PackageMatch.Success) { throw 'Could not read application ID/versionCode from APK manifest.' }
if ($PackageMatch.Groups[1].Value -ne $ExpectedPackageName -or $PackageMatch.Groups[2].Value -ne $ExpectedVersionCode) {
    throw "APK package/version mismatch. Expected $ExpectedPackageName/$ExpectedVersionCode; got $($PackageMatch.Groups[1].Value)/$($PackageMatch.Groups[2].Value)."
}
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
$env:ANDROID_APPLICATION_ID = $PackageName
$env:ANDROID_SERIAL = $DeviceId
if (-not (Test-Path -LiteralPath $Adb)) { throw "ADB executable not found at the configured path: $Adb" }

New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
$OriginalAirplane = $null
$OriginalWifi = $null
$NetworkStateCaptured = $false
$OfflineConfirmed = $false
$Report.Add("Started: $(Get-Date -Format o)")
$Report.Add("Required device serial: $DeviceId")
$Report.Add("Release APK: $ReleaseApkPath")
$Report.Add("Release APK SHA-256: $ActualApkSha256")
$Report.Add("Release APK package/versionCode: $PackageName/$ExpectedVersionCode")
$Report.Add("Artifact source commit: $SourceCommit")

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

function Invoke-ReleaseOfflineSmoke([string] $Phase) {
    $Report.Add("Release APK offline smoke started: $Phase at $(Get-Date -Format o)")
    Invoke-Adb @('-s', $DeviceId, 'logcat', '-c') | Out-Null
    Invoke-Adb @('-s', $DeviceId, 'shell', 'am', 'force-stop', $PackageName) | Out-Null
    Invoke-Adb @('-s', $DeviceId, 'shell', 'monkey', '-p', $PackageName, '1') | Out-Null
    Start-Sleep -Seconds 10
    $pid = Invoke-Adb @('-s', $DeviceId, 'shell', 'pidof', $PackageName)
    if (-not $pid) { throw "Release APK process did not remain alive during $Phase offline smoke." }

    $remoteXml = '/sdcard/espana-outdoor-release-window.xml'
    Invoke-Adb @('-s', $DeviceId, 'shell', 'uiautomator', 'dump', $remoteXml) | Out-Null
    $xmlText = Invoke-Adb @('-s', $DeviceId, 'shell', 'cat', $remoteXml)
    if ($xmlText -match 'No se pudo cargar el mapa|Reintentar') {
        throw "Release APK displayed the Mapbox loader error during $Phase offline smoke."
    }
    [xml]$document = $xmlText
    $mapNode = $document.SelectSingleNode("//node[@text='Mapa' or @content-desc='Mapa']")
    if (-not $mapNode) { throw "Release APK did not expose the Mapa destination during $Phase offline smoke." }
    $bounds = [regex]::Match($mapNode.GetAttribute('bounds'), '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]
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
    if ($Mode -eq 'offline' -and -not ($output | ForEach-Object { [string]$_ } | Select-String -Quiet 'MAPBOX_OFFLINE_MAP_RENDERED')) {
        throw 'The offline phase did not confirm Mapbox map rendering from the downloaded TileStore.'
    }
    $Report.Add("Phase passed: $Mode; explicit route origin=$source")
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

    Invoke-Adb @('-s', $DeviceId, 'install', '-r', $ReleaseApkPath) | Out-Null
    $installedPath = Invoke-Adb @('-s', $DeviceId, 'shell', 'pm', 'path', $PackageName)
    if ($installedPath -notmatch [regex]::Escape($PackageName)) {
        throw "The exact release APK did not install as $PackageName."
    }
    $installedDump = Invoke-Adb @('-s', $DeviceId, 'shell', 'dumpsys', 'package', $PackageName)
    if ($installedDump -notmatch "versionCode=$ExpectedVersionCode\\b") {
        throw "Installed package versionCode does not match the CI manifest ($ExpectedVersionCode)."
    }
    $Report.Add("PASS: exact release APK installed; sha256=$ActualApkSha256")

    & flutter pub get --enforce-lockfile
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get --enforce-lockfile failed.' }
    $python = if (Get-Command python -ErrorAction SilentlyContinue) { (Get-Command python).Source } elseif (Get-Command py -ErrorAction SilentlyContinue) { (Get-Command py).Source } else { $null }
    if (-not $python) { throw 'Python 3 is required for the Mapbox compatibility patch checks.' }
    if ((Split-Path -Leaf $python) -eq 'py.exe') {
        & $python -3 tool/test_patch_mapbox_resource_expiry.py
        if ($LASTEXITCODE -ne 0) { throw 'Mapbox resource-expiry patch tests failed.' }
        & $python -3 tool/patch_mapbox_resource_expiry.py
        if ($LASTEXITCODE -ne 0) { throw 'Mapbox resource-expiry patch failed.' }
        & $python -3 tool/verify_mapbox_lock.py
    } else {
        & $python tool/test_patch_mapbox_resource_expiry.py
        if ($LASTEXITCODE -ne 0) { throw 'Mapbox resource-expiry patch tests failed.' }
        & $python tool/patch_mapbox_resource_expiry.py
        if ($LASTEXITCODE -ne 0) { throw 'Mapbox resource-expiry patch failed.' }
        & $python tool/verify_mapbox_lock.py
    }
    if ($LASTEXITCODE -ne 0) { throw 'Mapbox lockfile verification failed.' }
    Invoke-RouteIntegration 'online_and_download'

    Set-AirplaneMode $true
    Invoke-Adb @('-s', $DeviceId, 'shell', 'svc', 'wifi', 'disable') | Out-Null
    Start-Sleep -Seconds 3
    $wifi = Invoke-Adb @('-s', $DeviceId, 'shell', 'settings', 'get', 'global', 'wifi_on')
    if ($wifi -ne '0') { throw "Wi-Fi is still enabled (wifi_on=$wifi); offline test refused." }
    Invoke-Adb @('-s', $DeviceId, 'shell', 'am', 'force-stop', $PackageName) | Out-Null
    Invoke-RouteIntegration 'offline'
    # Reinstall the exact release-mode APK after the debug integration test.
    # The update must preserve the downloaded TileStore; a signing mismatch
    # fails closed rather than uninstalling and erasing the region.
    Invoke-Adb @('-s', $DeviceId, 'install', '-r', $ReleaseApkPath) | Out-Null
    $Report.Add('PASS: exact release APK reinstalled over the integration test app without uninstalling app data.')
    Invoke-ReleaseOfflineSmoke 'post-integration'
    $airplaneNow = Invoke-Adb @('-s', $DeviceId, 'shell', 'settings', 'get', 'global', 'airplane_mode_on')
    $wifiNow = Invoke-Adb @('-s', $DeviceId, 'shell', 'settings', 'get', 'global', 'wifi_on')
    if ($airplaneNow -ne '1' -or $wifiNow -ne '0') { throw 'Connectivity changed during the offline route request.' }

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
        Invoke-Adb @('-s', $DeviceId, 'install', '-r', $ReleaseApkPath) | Out-Null
        Invoke-ReleaseOfflineSmoke 'post-reboot'
        $Report.Add("PASS: offline TileStore persisted after reboot; exact release APK relaunched offline at $(Get-Date -Format o)")
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
) { $Manifest[$matches[1]] = $matches[2] }
}
$RequiredManifestKeys = @(
    'apk_sha256',
    'application_id',
    'version_code',
    'source_commit',
    'mapbox_runtime_token',
    'mapbox_downloads_token',
    'validation_scope'
)
foreach ($key in $RequiredManifestKeys) {
    if (-not $Manifest.ContainsKey($key) -or -not $Manifest[$key]) {
        throw "Android validation manifest is missing required field '$key'."
    }
}
if ($Manifest['mapbox_runtime_token'] -ne 'available' -or
    $Manifest['mapbox_downloads_token'] -ne 'available' -or
    $Manifest['validation_scope'] -ne 'runtime-capable-artifact') {
    throw 'The selected artifact was not built with both Mapbox credentials and runtime validation scope.'
}
$ActualApkSha256 = (Get-FileHash -LiteralPath $ReleaseApkPath -Algorithm SHA256).Hash.ToLowerInvariant()
$ExpectedApkSha256 = $Manifest['apk_sha256'].ToLowerInvariant()
if ($ActualApkSha256 -ne $ExpectedApkSha256) {
    throw "APK SHA-256 mismatch. Expected $ExpectedApkSha256; got $ActualApkSha256."
}
$ExpectedPackageName = $Manifest['application_id']
$ExpectedVersionCode = $Manifest['version_code']
$SourceCommit = $Manifest['source_commit']
$CurrentSourceCommit = (& git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $CurrentSourceCommit -ne $SourceCommit) {
    throw "Checkout commit does not match the artifact source commit. Expected $SourceCommit; got $CurrentSourceCommit."
}
if ($env:ANDROID_APPLICATION_ID -and $env:ANDROID_APPLICATION_ID -ne $ExpectedPackageName) {
    throw "ANDROID_APPLICATION_ID '$env:ANDROID_APPLICATION_ID' does not match APK package '$ExpectedPackageName'."
}
$PackageName = $ExpectedPackageName
$SdkRoot = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { $null }
if (-not $SdkRoot) { throw 'Set ANDROID_SDK_ROOT or ANDROID_HOME to verify the APK package/version.' }
$AaptCandidates = Get-ChildItem -Path (Join-Path $SdkRoot 'build-tools') -Filter 'aapt.exe' -Recurse -File -ErrorAction SilentlyContinue
$Aapt = $AaptCandidates | Sort-Object { [version]$_.Directory.Name } -Descending | Select-Object -First 1
if (-not $Aapt) { throw 'Android build-tools aapt.exe was not found.' }
$Badging = & $Aapt.FullName dump badging $ReleaseApkPath 2>&1
if ($LASTEXITCODE -ne 0) { throw "aapt could not inspect APK: $($Badging | Out-String)" }
$BadgingText = $Badging -join "`n"
$PackageMatch = [regex]::Match($BadgingText, "package: name='([^']+)' versionCode='([^']+)'")
if (-not $PackageMatch.Success) { throw 'Could not read application ID/versionCode from the APK manifest.' }
if ($PackageMatch.Groups[1].Value -ne $ExpectedPackageName -or
    $PackageMatch.Groups[2].Value -ne $ExpectedVersionCode) {
    throw "APK package/version mismatch. Manifest expects $ExpectedPackageName/$ExpectedVersionCode; APK is $($PackageMatch.Groups[1].Value)/$($PackageMatch.Groups[2].Value)."
}
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
    if ($Mode -eq 'offline' -and -not ($output | ForEach-Object { [string]$_ } | Select-String -Quiet 'MAPBOX_OFFLINE_MAP_RENDERED')) {
        throw 'The offline phase did not confirm Mapbox map rendering from the downloaded TileStore.'
    }
    $Report.Add("Phase passed: $Mode; explicit route origin=$source")
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
)
    if (-not $bounds.Success) { throw 'Could not determine the Mapa destination tap bounds.' }
    $tapX = [int](($bounds.Groups[1].Value | ForEach-Object { [int]$_ }) + ([int]$bounds.Groups[3].Value - [int]$bounds.Groups[1].Value) / 2)
    $tapY = [int](([int]$bounds.Groups[2].Value + [int]$bounds.Groups[4].Value) / 2)
    Invoke-Adb @('-s', $DeviceId, 'shell', 'input', 'tap', "$tapX", "$tapY") | Out-Null
    Start-Sleep -Seconds 15

    $postXml = Invoke-Adb @('-s', $DeviceId, 'shell', 'uiautomator', 'dump', $remoteXml) | Out-Null
    $postText = Invoke-Adb @('-s', $DeviceId, 'shell', 'cat', $remoteXml)
    if ($postText -match 'No se pudo cargar el mapa|Reintentar') {
        throw "Release APK displayed the Mapbox loader error after opening Mapa during $Phase offline smoke."
    }
    $logcat = Invoke-Adb @('-s', $DeviceId, 'logcat', '-d')
    if ($logcat -match 'FATAL EXCEPTION|Fatal signal [0-9]+ \((SIGSEGV|SIGABRT)\)|Abort message:|backtrace:') {
        throw "Release APK crashed during $Phase offline smoke."
    }
    $remoteScreenshot = '/sdcard/espana-outdoor-release-offline.png'
    $localScreenshot = Join-Path $ReportDir ("release-offline-" + $Phase + ".png")
    Invoke-Adb @('-s', $DeviceId, 'shell', 'screencap', '-p', $remoteScreenshot) | Out-Null
    Invoke-Adb @('-s', $DeviceId, 'pull', $remoteScreenshot, $localScreenshot) | Out-Null
    if (-not (Test-Path -LiteralPath $localScreenshot) -or (Get-Item -LiteralPath $localScreenshot).Length -lt 1024) {
        throw 'Release APK offline screenshot was not captured.'
    }
    $Report.Add("PASS: exact release APK relaunched and opened Mapa offline ($Phase); screenshot=$localScreenshot")
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
    if ($Mode -eq 'offline' -and -not ($output | ForEach-Object { [string]$_ } | Select-String -Quiet 'MAPBOX_OFFLINE_MAP_RENDERED')) {
        throw 'The offline phase did not confirm Mapbox map rendering from the downloaded TileStore.'
    }
    $Report.Add("Phase passed: $Mode; explicit route origin=$source")
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

    Invoke-Adb @('-s', $DeviceId, 'install', '-r', $ReleaseApkPath) | Out-Null
    $installedPath = Invoke-Adb @('-s', $DeviceId, 'shell', 'pm', 'path', $PackageName)
    if ($installedPath -notmatch [regex]::Escape($PackageName)) {
        throw "The exact release APK did not install as $PackageName."
    }
    $installedDump = Invoke-Adb @('-s', $DeviceId, 'shell', 'dumpsys', 'package', $PackageName)
    if ($installedDump -notmatch "versionCode=$ExpectedVersionCode\\b") {
        throw "Installed package versionCode does not match the CI manifest ($ExpectedVersionCode)."
    }
    $Report.Add("PASS: exact release APK installed; sha256=$ActualApkSha256")

    & flutter pub get --enforce-lockfile
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get --enforce-lockfile failed.' }
    $python = if (Get-Command python -ErrorAction SilentlyContinue) { (Get-Command python).Source } elseif (Get-Command py -ErrorAction SilentlyContinue) { (Get-Command py).Source } else { $null }
    if (-not $python) { throw 'Python 3 is required for the Mapbox compatibility patch checks.' }
    if ((Split-Path -Leaf $python) -eq 'py.exe') {
        & $python -3 tool/test_patch_mapbox_resource_expiry.py
        if ($LASTEXITCODE -ne 0) { throw 'Mapbox resource-expiry patch tests failed.' }
        & $python -3 tool/patch_mapbox_resource_expiry.py
        if ($LASTEXITCODE -ne 0) { throw 'Mapbox resource-expiry patch failed.' }
        & $python -3 tool/verify_mapbox_lock.py
    } else {
        & $python tool/test_patch_mapbox_resource_expiry.py
        if ($LASTEXITCODE -ne 0) { throw 'Mapbox resource-expiry patch tests failed.' }
        & $python tool/patch_mapbox_resource_expiry.py
        if ($LASTEXITCODE -ne 0) { throw 'Mapbox resource-expiry patch failed.' }
        & $python tool/verify_mapbox_lock.py
    }
    if ($LASTEXITCODE -ne 0) { throw 'Mapbox lockfile verification failed.' }
    Invoke-RouteIntegration 'online_and_download'

    Set-AirplaneMode $true
    Invoke-Adb @('-s', $DeviceId, 'shell', 'svc', 'wifi', 'disable') | Out-Null
    Start-Sleep -Seconds 3
    $wifi = Invoke-Adb @('-s', $DeviceId, 'shell', 'settings', 'get', 'global', 'wifi_on')
    if ($wifi -ne '0') { throw "Wi-Fi is still enabled (wifi_on=$wifi); offline test refused." }
    Invoke-Adb @('-s', $DeviceId, 'shell', 'am', 'force-stop', $PackageName) | Out-Null
    Invoke-RouteIntegration 'offline'
    # Reinstall the exact release-mode APK after the debug integration test.
    # The update must preserve the downloaded TileStore; a signing mismatch
    # fails closed rather than uninstalling and erasing the region.
    Invoke-Adb @('-s', $DeviceId, 'install', '-r', $ReleaseApkPath) | Out-Null
    $Report.Add('PASS: exact release APK reinstalled over the integration test app without uninstalling app data.')
    Invoke-ReleaseOfflineSmoke 'post-integration'
    $airplaneNow = Invoke-Adb @('-s', $DeviceId, 'shell', 'settings', 'get', 'global', 'airplane_mode_on')
    $wifiNow = Invoke-Adb @('-s', $DeviceId, 'shell', 'settings', 'get', 'global', 'wifi_on')
    if ($airplaneNow -ne '1' -or $wifiNow -ne '0') { throw 'Connectivity changed during the offline route request.' }

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
        Invoke-Adb @('-s', $DeviceId, 'install', '-r', $ReleaseApkPath) | Out-Null
        Invoke-ReleaseOfflineSmoke 'post-reboot'
        $Report.Add("PASS: offline TileStore persisted after reboot; exact release APK relaunched offline at $(Get-Date -Format o)")
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
) { $Manifest[$matches[1]] = $matches[2] }
}
$RequiredManifestKeys = @(
    'apk_sha256',
    'application_id',
    'version_code',
    'source_commit',
    'mapbox_runtime_token',
    'mapbox_downloads_token',
    'validation_scope'
)
foreach ($key in $RequiredManifestKeys) {
    if (-not $Manifest.ContainsKey($key) -or -not $Manifest[$key]) {
        throw "Android validation manifest is missing required field '$key'."
    }
}
if ($Manifest['mapbox_runtime_token'] -ne 'available' -or
    $Manifest['mapbox_downloads_token'] -ne 'available' -or
    $Manifest['validation_scope'] -ne 'runtime-capable-artifact') {
    throw 'The selected artifact was not built with both Mapbox credentials and runtime validation scope.'
}
$ActualApkSha256 = (Get-FileHash -LiteralPath $ReleaseApkPath -Algorithm SHA256).Hash.ToLowerInvariant()
$ExpectedApkSha256 = $Manifest['apk_sha256'].ToLowerInvariant()
if ($ActualApkSha256 -ne $ExpectedApkSha256) {
    throw "APK SHA-256 mismatch. Expected $ExpectedApkSha256; got $ActualApkSha256."
}
$ExpectedPackageName = $Manifest['application_id']
$ExpectedVersionCode = $Manifest['version_code']
$SourceCommit = $Manifest['source_commit']
$CurrentSourceCommit = (& git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $CurrentSourceCommit -ne $SourceCommit) {
    throw "Checkout commit does not match the artifact source commit. Expected $SourceCommit; got $CurrentSourceCommit."
}
if ($env:ANDROID_APPLICATION_ID -and $env:ANDROID_APPLICATION_ID -ne $ExpectedPackageName) {
    throw "ANDROID_APPLICATION_ID '$env:ANDROID_APPLICATION_ID' does not match APK package '$ExpectedPackageName'."
}
$PackageName = $ExpectedPackageName
$SdkRoot = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { $null }
if (-not $SdkRoot) { throw 'Set ANDROID_SDK_ROOT or ANDROID_HOME to verify the APK package/version.' }
$AaptCandidates = Get-ChildItem -Path (Join-Path $SdkRoot 'build-tools') -Filter 'aapt.exe' -Recurse -File -ErrorAction SilentlyContinue
$Aapt = $AaptCandidates | Sort-Object { [version]$_.Directory.Name } -Descending | Select-Object -First 1
if (-not $Aapt) { throw 'Android build-tools aapt.exe was not found.' }
$Badging = & $Aapt.FullName dump badging $ReleaseApkPath 2>&1
if ($LASTEXITCODE -ne 0) { throw "aapt could not inspect APK: $($Badging | Out-String)" }
$BadgingText = $Badging -join "`n"
$PackageMatch = [regex]::Match($BadgingText, "package: name='([^']+)' versionCode='([^']+)'")
if (-not $PackageMatch.Success) { throw 'Could not read application ID/versionCode from the APK manifest.' }
if ($PackageMatch.Groups[1].Value -ne $ExpectedPackageName -or
    $PackageMatch.Groups[2].Value -ne $ExpectedVersionCode) {
    throw "APK package/version mismatch. Manifest expects $ExpectedPackageName/$ExpectedVersionCode; APK is $($PackageMatch.Groups[1].Value)/$($PackageMatch.Groups[2].Value)."
}
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
    if ($Mode -eq 'offline' -and -not ($output | ForEach-Object { [string]$_ } | Select-String -Quiet 'MAPBOX_OFFLINE_MAP_RENDERED')) {
        throw 'The offline phase did not confirm Mapbox map rendering from the downloaded TileStore.'
    }
    $Report.Add("Phase passed: $Mode; explicit route origin=$source")
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

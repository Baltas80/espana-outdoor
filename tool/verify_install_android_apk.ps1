param(
    [Parameter(Mandatory = $true)][string]$ReleaseApkPath,
    [Parameter(Mandatory = $true)][string]$ValidationManifestPath,
    [string]$DeviceSerial = $(if ($env:ANDROID_SERIAL) { $env:ANDROID_SERIAL } else { 'da09ac8c' }),
    [string]$ExpectedModel = $(if ($env:EXPECTED_ANDROID_MODEL) { $env:EXPECTED_ANDROID_MODEL } else { 'CPH2009' }),
    [switch]$OfflineSmoke,
    [switch]$RebootAfterInstall
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot
$ReleaseApkPath = (Resolve-Path -LiteralPath $ReleaseApkPath).Path
$ValidationManifestPath = (Resolve-Path -LiteralPath $ValidationManifestPath).Path
$Manifest = @{}
Get-Content -LiteralPath $ValidationManifestPath | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') { $Manifest[$matches[1]] = $matches[2] }
}
$RequiredKeys = @('apk_sha256', 'application_id', 'version_code', 'source_commit', 'mapbox_runtime_token', 'mapbox_downloads_token', 'validation_scope')
foreach ($key in $RequiredKeys) {
    if (-not $Manifest.ContainsKey($key) -or -not $Manifest[$key]) { throw "Validation manifest is missing '$key'." }
}
if ($Manifest['validation_scope'] -ne 'runtime-capable-artifact' -or $Manifest['mapbox_runtime_token'] -ne 'available' -or $Manifest['mapbox_downloads_token'] -ne 'available') {
    throw 'Artifact was not built with both Mapbox credentials and runtime validation enabled.'
}
$ActualHash = (Get-FileHash -LiteralPath $ReleaseApkPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($ActualHash -ne $Manifest['apk_sha256'].ToLowerInvariant()) { throw 'APK SHA-256 does not match the CI validation manifest.' }
$PackageName = $Manifest['application_id']
$ExpectedVersionCode = $Manifest['version_code']
$SourceCommit = $Manifest['source_commit']
$CurrentCommit = (& git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $CurrentCommit -ne $SourceCommit) { throw "Checkout must be source commit $SourceCommit; found $CurrentCommit." }
if ($env:ANDROID_APPLICATION_ID -and $env:ANDROID_APPLICATION_ID -ne $PackageName) { throw 'ANDROID_APPLICATION_ID does not match the artifact manifest.' }
$SdkRoot = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { $null }
if (-not $SdkRoot) { throw 'Set ANDROID_SDK_ROOT or ANDROID_HOME.' }
$AaptCandidates = Get-ChildItem -Path (Join-Path $SdkRoot 'build-tools') -Filter 'aapt.exe' -Recurse -File -ErrorAction SilentlyContinue
$Aapt = $AaptCandidates | Sort-Object { [version]$_.Directory.Name } -Descending | Select-Object -First 1
if (-not $Aapt) { throw 'Android build-tools aapt.exe was not found.' }
$Badging = & $Aapt.FullName dump badging $ReleaseApkPath 2>&1
if ($LASTEXITCODE -ne 0) { throw 'aapt failed to inspect the APK.' }
$BadgingText = $Badging -join "`n"
$Match = [regex]::Match($BadgingText, "package: name='([^']+)' versionCode='([^']+)'")
if (-not $Match.Success -or $Match.Groups[1].Value -ne $PackageName -or $Match.Groups[2].Value -ne $ExpectedVersionCode) {
    throw 'APK application ID/versionCode does not match the CI validation manifest.'
}
$AdbCommand = if ($env:ADB) { $env:ADB } else { (Get-Command adb -ErrorAction SilentlyContinue).Source }
if (-not $AdbCommand -or -not (Test-Path -LiteralPath $AdbCommand)) { throw 'ADB was not found. Add platform-tools to PATH or set ADB.' }
$Adb = $AdbCommand
$ReportDir = Join-Path $RepoRoot 'build\mapbox-oppo-validation'
New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
$ReportPath = Join-Path $ReportDir 'release-apk-install-report.txt'
$Report = [System.Collections.Generic.List[string]]::new()
$RouteEvidencePath = Join-Path $ReportDir 'validation-report.txt'
if ($OfflineSmoke) {
    if (-not (Test-Path -LiteralPath $RouteEvidencePath)) {
        throw "OfflineSmoke requires a successful route/download report first: run tool/test_mapbox_oppo_routes.ps1."
    }
    $routeEvidence = Get-Content -LiteralPath $RouteEvidencePath -Raw
    $requiredRouteEvidence = @(
        "Device verified: OPPO $ExpectedModel ($DeviceSerial)",
        "Source commit: $SourceCommit",
        "Application ID: $PackageName",
        "MAPBOX_ROUTE_VALIDATION source=online",
        "MAPBOX_OFFLINE_REGION_READY id=espana-outdoor-cordoba-poc",
        "MAPBOX_ROUTE_VALIDATION source=offline",
        "PASS: fresh native offline route confirmed"
    )
    foreach ($marker in $requiredRouteEvidence) {
        if (-not $routeEvidence.Contains($marker)) {
            throw "OfflineSmoke route evidence is missing or belongs to another device/build: $marker"
        }
    }
    $routeDiagnostics = ($routeEvidence -split "`r?`n") |
        Where-Object { $_ -match 'MAPBOX_OFFLINE_MAP_DIAGNOSTICS' } |
        Select-Object -Last 1
    if (-not $routeDiagnostics) { throw 'OfflineSmoke route report has no Mapbox render diagnostics.' }
    foreach ($marker in @('style_loaded=true','map_loaded=true','full_frame=true','idle=true','load_errors=0','resource_failures=0')) {
        if ($routeDiagnostics -notmatch [regex]::Escape($marker)) {
            throw "OfflineSmoke route report does not prove '$marker'."
        }
    }
    if ($RebootAfterInstall -and $routeEvidence -notmatch 'PASS: offline TileStore and routing persisted after device reboot') {
        throw 'RebootAfterInstall requires route/download evidence that already survived a device reboot.'
    }
    $Report.Add("Offline integration evidence verified: $RouteEvidencePath")
}
$OriginalAirplane = $null
$OriginalWifi = $null
$NetworkCaptured = $false

function Invoke-Adb([string[]]$Arguments) {
    $output = & $Adb @Arguments
    if ($LASTEXITCODE -ne 0) { throw "ADB failed: adb $($Arguments -join ' ')" }
    return ($output | Out-String).Trim()
}

function Set-Airplane([bool]$Enabled) {
    $action = if ($Enabled) { 'enable' } else { 'disable' }
    & $Adb -s $DeviceSerial shell cmd connectivity airplane-mode $action | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $value = if ($Enabled) { '1' } else { '0' }
        $state = if ($Enabled) { 'true' } else { 'false' }
        Invoke-Adb @('-s', $DeviceSerial, 'shell', 'settings', 'put', 'global', 'airplane_mode_on', $value) | Out-Null
        Invoke-Adb @('-s', $DeviceSerial, 'shell', 'am', 'broadcast', '-a', 'android.intent.action.AIRPLANE_MODE', '--ez', 'state', $state) | Out-Null
    }
    $expected = if ($Enabled) { '1' } else { '0' }
    $actual = Invoke-Adb @('-s', $DeviceSerial, 'shell', 'settings', 'get', 'global', 'airplane_mode_on')
    if ($actual -ne $expected) { throw 'Airplane mode could not be verified.' }
}

$PythonCommand = if ($env:PYTHON) {
    $env:PYTHON
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
    (Get-Command python).Source
} elseif (Get-Command py -ErrorAction SilentlyContinue) {
    (Get-Command py).Source
} else {
    $null
}
if (-not $PythonCommand -or -not (Test-Path -LiteralPath $PythonCommand)) {
    throw 'Python 3 is required for the Android screenshot validation gate.'
}
$PythonLauncherArgs = if ((Split-Path -Leaf $PythonCommand) -eq 'py.exe') { @('-3') } else { @() }

function Launch-And-Capture([string]$Phase) {
    Invoke-Adb @('-s', $DeviceSerial, 'logcat', '-c') | Out-Null
    Invoke-Adb @('-s', $DeviceSerial, 'shell', 'am', 'force-stop', $PackageName) | Out-Null
    Invoke-Adb @('-s', $DeviceSerial, 'shell', 'monkey', '-p', $PackageName, '1') | Out-Null
    Start-Sleep -Seconds 10
    $processId = Invoke-Adb @('-s', $DeviceSerial, 'shell', 'pidof', $PackageName)
    if (-not $processId) { throw "Release APK process did not remain alive ($Phase)." }
    $remoteXml = '/sdcard/espana-outdoor-release-window.xml'
    Invoke-Adb @('-s', $DeviceSerial, 'shell', 'uiautomator', 'dump', $remoteXml) | Out-Null
    $xmlText = Invoke-Adb @('-s', $DeviceSerial, 'shell', 'cat', $remoteXml)
    if ($xmlText -match 'No se pudo cargar el mapa|Reintentar') { throw "Mapbox loader error is visible ($Phase)." }
    [xml]$document = $xmlText
    $mapNode = $document.SelectSingleNode("//node[@text='Mapa' or @content-desc='Mapa']")
    if (-not $mapNode) { throw "The Mapa destination is not exposed by the release APK ($Phase)." }
    $bounds = [regex]::Match($mapNode.GetAttribute('bounds'), '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
    if (-not $bounds.Success) { throw 'Could not parse the Mapa destination bounds.' }
    $x1 = [int]$bounds.Groups[1].Value
    $y1 = [int]$bounds.Groups[2].Value
    $x2 = [int]$bounds.Groups[3].Value
    $y2 = [int]$bounds.Groups[4].Value
    $tapX = [int](($x1 + $x2) / 2)
    $tapY = [int](($y1 + $y2) / 2)
    Invoke-Adb @('-s', $DeviceSerial, 'shell', 'input', 'tap', "$tapX", "$tapY") | Out-Null
    Start-Sleep -Seconds 15
    Invoke-Adb @('-s', $DeviceSerial, 'shell', 'uiautomator', 'dump', $remoteXml) | Out-Null
    $postText = Invoke-Adb @('-s', $DeviceSerial, 'shell', 'cat', $remoteXml)
    if ($postText -match 'No se pudo cargar el mapa|Reintentar') { throw "Mapbox loader error appeared after opening Mapa ($Phase)." }
    [xml]$postDocument = $postText
    if (-not $postDocument.SelectSingleNode("//node[@text='Mapa']")) {
        throw "The release APK did not reach the Mapa page ($Phase)."
    }
    $pidAfterMap = Invoke-Adb @('-s', $DeviceSerial, 'shell', 'pidof', $PackageName)
    if (-not $pidAfterMap) { throw "Release APK exited after opening Mapa ($Phase)." }
    $logcat = Invoke-Adb @('-s', $DeviceSerial, 'logcat', '-d')
    if ($logcat -match 'FATAL EXCEPTION|Fatal signal [0-9]+ \((SIGSEGV|SIGABRT)\)|Abort message:') { throw "Release APK crashed ($Phase)." }
    foreach ($marker in @('MAPBOX_MAP_STYLE_LOADED','MAPBOX_MAP_LOADED','MAPBOX_MAP_FULL_FRAME','MAPBOX_MAP_IDLE')) {
        if (-not $logcat.Contains($marker)) { throw "Release map did not emit $marker ($Phase)." }
    }
    if ($logcat -match 'MAPBOX_MAP_LOAD_ERROR') { throw "Release map reported a Mapbox load error ($Phase)." }
    if ($OfflineSmoke -and $logcat -match 'MAPBOX_RESOURCE_FAILURE') {
        throw "Release map reported failed offline resources ($Phase)."
    }
    $sanitizedLogcat = [regex]::Replace($logcat, '(?i)(pk|sk)\.[A-Za-z0-9._~-]{10,}', '$1.<REDACTED>')
    $sanitizedLogcat = [regex]::Replace($sanitizedLogcat, '(?i)(access_token=)[^&\s]+', '$1[REDACTED]')
    $logcatPath = Join-Path $ReportDir ("release-map-$Phase-logcat.txt")
    $sanitizedLogcat | Set-Content -LiteralPath $logcatPath -Encoding utf8
    $remotePng = '/sdcard/espana-outdoor-release-map.png'
    $localPng = Join-Path $ReportDir ("release-map-$Phase.png")
    Invoke-Adb @('-s', $DeviceSerial, 'shell', 'screencap', '-p', $remotePng) | Out-Null
    Invoke-Adb @('-s', $DeviceSerial, 'pull', $remotePng, $localPng) | Out-Null
    if (-not (Test-Path -LiteralPath $localPng) -or (Get-Item -LiteralPath $localPng).Length -lt 1024) { throw 'Release map screenshot is missing or too small.' }
    $gateOutput = & $PythonCommand @PythonLauncherArgs (Join-Path $RepoRoot 'tool\verify_android_map_screenshot.py') $localPng 2>&1
    $gateExitCode = $LASTEXITCODE
    $gateOutput | ForEach-Object { $Report.Add([string]$_) }
    if ($gateExitCode -ne 0) { throw "Release map screenshot failed the visual acceptance gate ($Phase)." }
    $Report.Add("PASS: release APK rendered the Córdoba map ($Phase); screenshot=$localPng; logcat=$logcatPath")
    $Report.Add('Required Mapbox style-loaded, map-loaded, full-frame and idle callbacks were observed.')
    $Report.Add('No fatal application/native crash markers or offline resource failures were found.')
}

try {
    $deviceList = Invoke-Adb @('devices', '-l')
    $devicePattern = '^' + [regex]::Escape($DeviceSerial) + '\s+device\b'
    if (-not ($deviceList -split "`r?`n" | Where-Object { $_ -match $devicePattern })) { throw "Device $DeviceSerial is not authorized/online." }
    $brand = Invoke-Adb @('-s', $DeviceSerial, 'shell', 'getprop', 'ro.product.brand')
    $model = Invoke-Adb @('-s', $DeviceSerial, 'shell', 'getprop', 'ro.product.model')
    if ($brand -ne 'OPPO' -or $model -ne $ExpectedModel) { throw "Expected OPPO $ExpectedModel; detected $brand $model." }
    $OriginalAirplane = Invoke-Adb @('-s', $DeviceSerial, 'shell', 'settings', 'get', 'global', 'airplane_mode_on')
    $OriginalWifi = Invoke-Adb @('-s', $DeviceSerial, 'shell', 'settings', 'get', 'global', 'wifi_on')
    if ($OriginalAirplane -notin @('0','1') -or $OriginalWifi -notin @('0','1')) { throw 'Could not read original network state.' }
    $NetworkCaptured = $true
    $Report.Add("Device: $brand $model ($DeviceSerial)")
    $Report.Add("Artifact commit: $SourceCommit")
    $Report.Add("APK SHA-256: $ActualHash")
    $Report.Add("Package/versionCode: $PackageName/$ExpectedVersionCode")
    Invoke-Adb @('-s', $DeviceSerial, 'install', '-r', $ReleaseApkPath) | Out-Null
    $installedPath = Invoke-Adb @('-s', $DeviceSerial, 'shell', 'pm', 'path', $PackageName)
    $basePathLine = ($installedPath -split "`r?`n" | Where-Object { $_ -match '^package:' } | Select-Object -First 1)
    if (-not $basePathLine) { throw 'Android did not return an installed base APK path for the expected package.' }
    $remoteBaseApk = $basePathLine -replace '^package:', ''
    $installedDump = Invoke-Adb @('-s', $DeviceSerial, 'shell', 'dumpsys', 'package', $PackageName)
    if ($installedDump -notmatch "versionCode=$ExpectedVersionCode\b") { throw 'Installed versionCode does not match the artifact manifest.' }
    $installedBaseApk = Join-Path $ReportDir 'installed-base.apk'
    Invoke-Adb @('-s', $DeviceSerial, 'pull', $remoteBaseApk, $installedBaseApk) | Out-Null
    $installedBaseHash = (Get-FileHash -LiteralPath $installedBaseApk -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($installedBaseHash -ne $ActualHash) { throw 'Installed base.apk SHA-256 does not match the exact CI artifact.' }
    $Report.Add("Installed base APK SHA-256: $installedBaseHash")
    $Report.Add('PASS: exact CI APK installed and verified without uninstalling app data.')
    if ($OfflineSmoke) {
        Set-Airplane $true
        Invoke-Adb @('-s', $DeviceSerial, 'shell', 'svc', 'wifi', 'disable') | Out-Null
        Start-Sleep -Seconds 3
        if ((Invoke-Adb @('-s', $DeviceSerial, 'shell', 'settings', 'get', 'global', 'wifi_on')) -ne '0') { throw 'Wi-Fi remained enabled; offline smoke aborted.' }
    }
    $installedPhase = if ($OfflineSmoke) { 'offline-installed' } else { 'online-installed' }
    Launch-And-Capture $installedPhase
    if ($RebootAfterInstall) {
        Invoke-Adb @('-s', $DeviceSerial, 'reboot') | Out-Null
        Invoke-Adb @('-s', $DeviceSerial, 'wait-for-device') | Out-Null
        $deadline = (Get-Date).AddMinutes(3)
        $booted = $false
        while ((Get-Date) -lt $deadline) {
            try { if ((Invoke-Adb @('-s', $DeviceSerial, 'shell', 'getprop', 'sys.boot_completed')) -eq '1') { $booted = $true; break } } catch { }
            Start-Sleep -Seconds 3
        }
        if (-not $booted) { throw 'OPPO did not finish rebooting within three minutes.' }
        if ($OfflineSmoke) {
            Set-Airplane $true
            Invoke-Adb @('-s', $DeviceSerial, 'shell', 'svc', 'wifi', 'disable') | Out-Null
            Start-Sleep -Seconds 3
            if ((Invoke-Adb @('-s', $DeviceSerial, 'shell', 'settings', 'get', 'global', 'wifi_on')) -ne '0') { throw 'Wi-Fi remained enabled after reboot.' }
        }
        $rebootPhase = if ($OfflineSmoke) { 'offline-after-reboot' } else { 'online-after-reboot' }
        Launch-And-Capture $rebootPhase
        $Report.Add('PASS: release APK relaunched after reboot with original app data.')
    }
} catch {
    $Report.Add("FAIL: $($_.Exception.Message)")
    throw
} finally {
    if ($NetworkCaptured) {
        try { Set-Airplane ($OriginalAirplane -eq '1') } catch { $Report.Add('WARNING: could not restore airplane mode.') }
        try {
            $wifiAction = if ($OriginalWifi -eq '1') { 'enable' } else { 'disable' }
            Invoke-Adb @('-s', $DeviceSerial, 'shell', 'svc', 'wifi', $wifiAction) | Out-Null
        } catch { $Report.Add('WARNING: could not restore Wi-Fi state.') }
    }
    $Report | Set-Content -LiteralPath $ReportPath -Encoding utf8
}
Write-Host "PASS: exact APK $ActualHash installed on OPPO $ExpectedModel ($DeviceSerial)."
Write-Host "Report: $ReportPath"
$ErrorActionPreference = 'Stop'
$repoRoot = (Get-Location).Path
$patchRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Test-Path (Join-Path $repoRoot 'pubspec.yaml'))) {
  throw "Ejecuta este script desde la raíz del repositorio España Outdoor."
}
$targets = @(
  'lib/core/storage/route_recording_store.dart',
  'lib/core/location/route_recorder.dart',
  'lib/core/navigation/backtrack.dart',
  'test/core/route_recording_store_test.dart',
  'lib/features/navigation/backtrack_page.dart'
)
foreach ($target in $targets) {
  if (-not (Test-Path (Join-Path $repoRoot $target))) {
    throw "No existe $target. No se ha modificado ningún archivo."
  }
}
$pagePath = Join-Path $repoRoot 'lib/features/navigation/backtrack_page.dart'
$pageText = Get-Content -LiteralPath $pagePath -Raw
$oldLine = 'final guidance = location.position == null ? null : const BacktrackService().calculate(current: location.position!, recordedPoints: recording.points);'
if (-not $pageText.Contains($oldLine)) {
  throw "No se reconoce la versión esperada de backtrack_page.dart. No se ha modificado ningún archivo."
}
if ($pageText.Contains('backtrackGuidanceProvider')) {
  throw "La integración asíncrona ya parece estar aplicada. No se ha modificado ningún archivo."
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
foreach ($target in $targets) {
  $source = Join-Path $repoRoot $target
  Copy-Item -LiteralPath $source -Destination "$source.before-backtrack-$stamp.bak"
}

foreach ($target in @(
  'lib/core/storage/route_recording_store.dart',
  'lib/core/location/route_recorder.dart',
  'lib/core/navigation/backtrack.dart',
  'test/core/route_recording_store_test.dart'
)) {
  $source = Join-Path $patchRoot $target
  $destination = Join-Path $repoRoot $target
  Copy-Item -LiteralPath $source -Destination $destination -Force
}

$provider = @'
final backtrackGuidanceProvider =
    FutureProvider.family<BacktrackGuidance?, Position>((ref, current) async {
  final recorder = ref.read(routeRecorderProvider.notifier);
  return const BacktrackService().calculateFromStream(
    current: current,
    recordedPoints: recorder.pointsForBacktrack(),
  );
});

'@
$pageText = $pageText.Replace(
  'class BacktrackPage extends ConsumerWidget {',
  "$provider`r`nclass BacktrackPage extends ConsumerWidget {"
)
$newGuidance = @'
final guidanceAsync = location.position == null
        ? null
        : ref.watch(backtrackGuidanceProvider(location.position!));
    final guidance = guidanceAsync?.valueOrNull;
'@
$pageText = $pageText.Replace($oldLine, $newGuidance.TrimEnd())
Set-Content -LiteralPath $pagePath -Value $pageText -Encoding UTF8

Write-Output 'Parche aplicado a cinco archivos.'
Write-Output 'Se han creado copias .before-backtrack-<fecha>.bak.'
Write-Output 'No se han ejecutado pruebas ni se ha realizado commit/push.'

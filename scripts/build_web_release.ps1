. "$PSScriptRoot\build_config.ps1"

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..\client")
$pubspecPath = Join-Path $projectRoot "pubspec.yaml"
if (-not (Test-Path $pubspecPath)) {
  Write-Host "pubspec.yaml not found: $pubspecPath" -ForegroundColor Red
  exit 1
}

Push-Location $projectRoot
try {
  flutter build web --release `
    --no-web-resources-cdn `
    --pwa-strategy=none `
    --dart-define=AIRMONEY_API_PROXY_URL="$PROXY_URL" `
    --dart-define=AIRMONEY_API_KEY="$API_KEY"

  if ($LASTEXITCODE -ne 0) {
    Write-Host "Web build failed!" -ForegroundColor Red
    exit 1
  }

  $zipPath = Join-Path $PSScriptRoot "..\airmoney-web.zip"
  if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
  Compress-Archive -Path "build\web\*" -DestinationPath $zipPath -Force
} finally {
  Pop-Location
}

Write-Host ""
Write-Host "Web build done." -ForegroundColor Green
Write-Host "  config : scripts/build_config.ps1 (UseIpMode=$UseIpMode)"
Write-Host "  output : client/build/web/"
Write-Host "  zip    : $zipPath"
Write-Host "  deploy : Upload client/build/web/ or zip to money.air-inc.top"
Write-Host "  ip     : Web via http://122.51.10.98:8083 (before filing)"

. "$PSScriptRoot\build_config.ps1"

flutter build web --release `
  --dart-define=AIRMONEY_API_PROXY_URL="$PROXY_URL" `
  --dart-define=AIRMONEY_API_KEY="$API_KEY"

if ($LASTEXITCODE -ne 0) {
  Write-Host "Web build failed!" -ForegroundColor Red
  exit 1
}

$zipPath = Join-Path $PSScriptRoot "..\airmoney-web.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path "build\web\*" -DestinationPath $zipPath -Force

Write-Host ""
Write-Host "Web build done." -ForegroundColor Green
Write-Host "  config : scripts/build_config.ps1 (UseIpMode=$UseIpMode)"
Write-Host "  output : build/web/"
Write-Host "  zip    : $zipPath"
Write-Host "  deploy : Upload build/web/ or zip to money.air-inc.com"
Write-Host "  ip     : Web via http://122.51.10.98:8083 (before filing)"

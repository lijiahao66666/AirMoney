#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/../client"
if [ ! -f "${PROJECT_ROOT}/pubspec.yaml" ]; then
  echo "pubspec.yaml not found: ${PROJECT_ROOT}/pubspec.yaml" >&2
  exit 1
fi
cd "${PROJECT_ROOT}"

# 与 build_config.ps1 保持一致，备案前改为 1
USE_IP_MODE=0

if [ "$USE_IP_MODE" = "1" ]; then
  # 与 HTML 同站 8083，API 在 /api 路径
  PROXY_URL="http://122.51.10.98:8083/api"
else
  PROXY_URL="http://money.air-inc.top/api"
fi

# 与 server/.env 的 API_KEY 一致
API_KEY=""

flutter clean
flutter pub get

flutter build ipa --release \
  --dart-define=AIRMONEY_API_PROXY_URL="$PROXY_URL" \
  --dart-define=AIRMONEY_API_KEY="$API_KEY"

echo ""
echo "IPA build done. (UseIpMode=$USE_IP_MODE)"
echo "  output: client/build/ios/ipa/*.ipa"

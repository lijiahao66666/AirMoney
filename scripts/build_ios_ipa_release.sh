#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/../client"
if [ ! -f "${PROJECT_ROOT}/pubspec.yaml" ]; then
  echo "pubspec.yaml not found: ${PROJECT_ROOT}/pubspec.yaml" >&2
  exit 1
fi
cd "${PROJECT_ROOT}"

# 涓?build_config.ps1 淇濇寔涓€鑷达紝澶囨鍓嶆敼涓?1
USE_IP_MODE=0

if [ "$USE_IP_MODE" = "1" ]; then
  # 涓?HTML 鍚岀珯 8083锛孉PI 鍦?/api 璺緞
  PROXY_URL="http://122.51.10.98:8083/api"
else
  PROXY_URL="http://money.air-inc.top/api"
fi

# 涓?server/.env 鐨?API_KEY 涓€鑷?
API_KEY=""
BUILD_NUMBER="${BUILD_NUMBER:-$(date +"%Y%m%d%H")}"

flutter clean
flutter pub get

flutter build ipa --release \
  --build-number "$BUILD_NUMBER" \
  --dart-define=AIRMONEY_API_PROXY_URL="$PROXY_URL" \
  --dart-define=AIRMONEY_API_KEY="$API_KEY"



echo ""
echo "IPA build done. (UseIpMode=$USE_IP_MODE)"
echo "  output: client/build/ios/ipa/*.ipa"



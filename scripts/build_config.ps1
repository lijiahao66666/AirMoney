# AirMoney 鏋勫缓閰嶇疆 - Web / Android / iOS 鍏辩敤
# 鍒囨崲澶囨鍓?鍚庯細淇敼 $UseIpMode锛屾墍鏈夋墦鍖呰剼鏈細鍚屾浣跨敤
$UseIpMode = $false   # 澶囨鍓嶆敼涓?$true锛涘妗堝悗鏀逛负 $false

if ($UseIpMode) {
  $PROXY_URL = "http://122.51.10.98:8083/api"
} else {
  $PROXY_URL = "https://money.air-inc.top/api"
}

# API Key锛堜笌 server/.env 鐨?API_KEY 涓€鑷达紝鍚﹀垯绛惧埌绛夋帴鍙ｄ細杩斿洖 401锛?
$API_KEY = "af9a7d9ac145f539c84616012f9398b121cee1ad65005f3fc055f056aa4fd3fc"
$BUILD_NUMBER = $env:BUILD_NUMBER
if (-not $BUILD_NUMBER) { $BUILD_NUMBER = (Get-Date -Format "yyyyMMddHH") }

# AirMoney 构建配置 - Web / Android / iOS 共用
# 切换备案前/后：修改 $UseIpMode，所有打包脚本会同步使用
$UseIpMode = $true   # 备案前改为 $true；备案后改为 $false

if ($UseIpMode) {
  # 备案前：与 HTML 同站 8083，API 在 /api 路径
  $PROXY_URL = "http://122.51.10.98:8083/api"
} else {
  # 备案后：使用域名
  $PROXY_URL = "https://money.air-inc.com/api"
}

# API Key（与 server/.env 的 API_KEY 一致，否则签到等接口会返回 401）
$API_KEY = "af9a7d9ac145f539c84616012f9398b121cee1ad65005f3fc055f056aa4fd3fc"

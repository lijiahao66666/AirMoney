# AirMoney 部署说明

## 服务器配置（宝塔）

### money.air-inc.top（同站部署，参考 AirTranslate）

**一个站点同时提供 HTML 和 API**：

- **类型**：HTML 站点 + 反向代理
- **备案前**：绑定 `122.51.10.98:8083`
- **备案后**：money.air-inc.top:80
- **根路径**：Flutter Web 构建的静态文件
- **/api 路径**：反向代理到 `http://127.0.0.1:9002`（将 `/api/xxx` 转发到后端 `/xxx`）

### 3. 启动后端

```bash
cd server
cp .env.example .env   # 填写 TENCENT_SECRET_ID、TENCENT_SECRET_KEY、API_KEY
npm install   # 如需要
node app.js   # 或使用 pm2 守护
```

确保 PM2 或 systemd 将端口设为 9002。

## 打包

### 构建配置

编辑 `scripts/build_config.ps1`：

- `$UseIpMode = $true`：备案前，使用公网 IP
- `$UseIpMode = $false`：备案后，使用域名
- `$API_KEY`：与 server/.env 一致

### Web

```powershell
.\scripts\build_web_release.ps1
```

- 输出：`build/web/`、`airmoney-web.zip`
- 部署：将 `build/web/` 内容上传到 money.air-inc.top 站点根目录
- 备案前访问：http://122.51.10.98:8083

### Android APK

```powershell
.\scripts\build_android_apk_arm64_release.ps1
```

- 输出：`build/app/outputs/flutter-apk/app-release.apk`

### Android AAB（应用商店）

```powershell
.\scripts\build_android_aab_release.ps1
```

- 输出：`build/app/outputs/bundle/release/app-release.aab`

### iOS IPA（Mac）

```bash
chmod +x scripts/build_ios_ipa_release.sh
./scripts/build_ios_ipa_release.sh
```

- 编辑脚本中的 `USE_IP_MODE`、`API_KEY` 与 build_config.ps1 保持一致
- 输出：`build/ios/ipa/*.ipa`

## 端口汇总

| 服务       | 备案前 (IP)          | 备案后 (域名)              |
|------------|----------------------|----------------------------|
| Web + API  | 122.51.10.98:8083    | money.air-inc.top         |
| API 路径   | :8083/api            | /api                      |
| 后端进程   | 127.0.0.1:9002       | 127.0.0.1:9002            |

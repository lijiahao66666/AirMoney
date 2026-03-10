# AirMoney 閮ㄧ讲璇存槑

## 鏈嶅姟鍣ㄩ厤缃紙瀹濆锛?

### money.air-inc.top锛堝悓绔欓儴缃诧紝鍙傝€?AirTranslate锛?
**涓€涓珯鐐瑰悓鏃舵彁渚?HTML 鍜?API**锛?

- **绫诲瀷**锛欻TML 绔欑偣 + 鍙嶅悜浠ｇ悊
- **澶囨鍓?*锛氱粦瀹?`122.51.10.98:8083`
- **澶囨鍚?*锛歮oney.air-inc.top:80
- **鏍硅矾寰?*锛欶lutter Web 鏋勫缓鐨勯潤鎬佹枃浠?
- **/api 璺緞**锛氬弽鍚戜唬鐞嗗埌 `http://127.0.0.1:9002`锛堝皢 `/api/xxx` 杞彂鍒板悗绔?`/xxx`锛?

### 3. 鍚姩鍚庣

```bash
cd server
cp .env.example .env   # 濉啓 TENCENT_SECRET_ID銆乀ENCENT_SECRET_KEY銆丄PI_KEY
npm install   # 濡傞渶瑕?
node app.js   # 鎴栦娇鐢?pm2 瀹堟姢
```

纭繚 PM2 鎴?systemd 灏嗙鍙ｈ涓?9002銆?

## 鎵撳寘

### 鏋勫缓閰嶇疆

缂栬緫 `scripts/build_config.ps1`锛?

- `$UseIpMode = $true`锛氬妗堝墠锛屼娇鐢ㄥ叕缃?IP
- `$UseIpMode = $false`锛氬妗堝悗锛屼娇鐢ㄥ煙鍚?
- `$API_KEY`锛氫笌 server/.env 涓€鑷?

### Web

```powershell
.\scripts\build_web_release.ps1
```

- 杈撳嚭锛歚build/web/`銆乣airmoney-web.zip`
- 閮ㄧ讲锛氬皢 `build/web/` 鍐呭涓婁紶鍒?money.air-inc.top 绔欑偣鏍圭洰褰?- 澶囨鍓嶈闂細http://122.51.10.98:8083

### Android APK

```powershell
.\scripts\build_android_apk_arm64_release.ps1
```

- 杈撳嚭锛歚build/app/outputs/flutter-apk/app-release.apk`

### Android AAB锛堝簲鐢ㄥ晢搴楋級

```powershell
.\scripts\build_android_aab_release.ps1
```

- 杈撳嚭锛歚build/app/outputs/bundle/release/app-release.aab`

### iOS IPA锛圡ac锛?

```bash
chmod +x scripts/build_ios_ipa_release.sh
./scripts/build_ios_ipa_release.sh
```

- 缂栬緫鑴氭湰涓殑 `USE_IP_MODE`銆乣API_KEY` 涓?build_config.ps1 淇濇寔涓€鑷?
- 杈撳嚭锛歚build/ios/ipa/*.ipa`

## 绔彛姹囨€?

| 鏈嶅姟       | 澶囨鍓?(IP)          | 澶囨鍚?(鍩熷悕)              |
|------------|----------------------|----------------------------|
| Web + API  | 122.51.10.98:8083    | money.air-inc.top         |
| API 璺緞   | :8083/api            | /api                      |
| 鍚庣杩涚▼   | 127.0.0.1:9002       | 127.0.0.1:9002            |

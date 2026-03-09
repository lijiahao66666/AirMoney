# AirMoney锛堝搸鍛€閽憋級

鍦ㄦ剰浣犵殑姣忎竴绗旈挶銆?

鍩轰簬 Flutter 寮€鍙戠殑娑堣垂绠＄悊 App锛屼富鎵撲拱鍓嶅挩璇€佷拱鍚庤璐︿笌鍒嗘瀽鍙嶆€濄€?

## 浜у搧鏂规

璇﹁ [docs/PRODUCT_DESIGN.md](docs/PRODUCT_DESIGN.md)

## UI 璁捐

璇﹁ [docs/UI_DESIGN.md](docs/UI_DESIGN.md)

## 鎶€鏈爤

- **瀹㈡埛绔?*锛欶lutter
- **鏈湴瀛樺偍**锛歋QLite
- **鍚庣**锛歂ode.js锛圓PI 浠ｇ悊锛岃皟鐢ㄨ吘璁贩鍏冿級
- **澶фā鍨?*锛氳吘璁贩鍏?

## 蹇€熷紑濮?

### 1. 鍚姩鍚庣鏈嶅姟

```bash
cd server
cp .env.example .env   # 澶嶅埗骞跺～鍐?TENCENT_SECRET_ID銆乀ENCENT_SECRET_KEY 绛?
pm2 start ecosystem.config.cjs
```

榛樿绔彛 9001锛屾贩鍏?API銆佺Н鍒嗐€佺櫥褰曞潎鍦ㄦ鏈嶅姟涓€?

### 2. 杩愯 Flutter 搴旂敤

```bash
# 榛樿杩炴帴 localhost:9001
flutter run

# 鎴栨寚瀹?API 鍦板潃
flutter run --dart-define=AIRMONEY_API_PROXY_URL=http://your-server:9001 --dart-define=AIRMONEY_API_KEY=your_key
```

### 3. 澶嶇敤 AirRead 鍚庣锛堝彲閫夛級

鑻ュ凡閮ㄧ讲 AirRead 鍚庣锛屽彲灏?`AIRMONEY_API_PROXY_URL` 鎸囧悜鍚屼竴鍦板潃锛屾贩鍏冧唬鐞嗕笌绉垎浣撶郴閫氱敤銆?

## 妯″潡璇存槑

| 妯″潡 | 渚濊禆 | 璇存槑 |
|------|------|------|
| 璁拌处 | 鏃?| 鏈湴 SQLite锛屼笉渚濊禆缃戠粶 |
| 鍒嗘瀽 | 娣峰厓 + 绉垎 | 鍗曟鍒嗘瀽锛堣瀹屼竴绗旓級銆佸懆鏈熷垎鏋?|
| 鍜ㄨ | 娣峰厓 + 绉垎 | 涔板墠瀵硅瘽锛岃緭鍏ャ€屾垜鎯充拱 XX銆?|
| 绉垎 / 鐧诲綍 | 鍚庣 | 鍙傝€?AirRead 鐨勭Н鍒嗕笌鐧诲綍閫昏緫 |

## 椤圭洰缁撴瀯

```
lib/
鈹溾攢鈹€ core/theme/      # 涓婚涓庤壊褰?
鈹溾攢鈹€ data/            # 鏁版嵁搴撲笌妯″瀷
鈹溾攢鈹€ services/        # API銆佽璇併€佸垎鏋愩€佸挩璇?
鈹溾攢鈹€ presentation/    # 椤甸潰涓?Provider
鈹斺攢鈹€ main.dart
server/              # Node.js 鍚庣
docs/                # 浜у搧璁捐銆乁I 璁捐
```

## 服务端目录统一（2026-03）

AirMoney 的服务端文件统一放在 `server/` 目录下。服务器推荐目录结构：`/www/airmoney/server`。

首次启动：

```bash
cd /www/airmoney/server
cp .env.example .env
pm2 start ecosystem.config.cjs
pm2 save
```

日常更新：

```bash
cd /www/airmoney/server
pm2 restart airmoney
```

如果只是本地调试，也可以继续执行：

```bash
cd server
node app.js
```
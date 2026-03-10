# AirMoney Android 签名信息

## 包名 (Application ID)
```
top.airinc.airmoney
```

## 签名 MD5（用于微信开放平台等）
```
5D:8C:82:80:83:9E:F6:92:60:D3:2E:B2:01:C8:45:B4
```

## 签名 SHA-1（用于 Google Play / Firebase）
```
C2:6F:B2:3B:C0:21:AD:DD:6B:33:DB:B3:43:D0:6E:B0:60:09:EA:83
```

## 签名 SHA-256
```
9B:E4:48:29:A4:BE:DA:92:03:87:28:F7:FE:4B:7C:9D:A7:AA:5F:6E:13:42:05:41:D1:BA:2E:12:4C:5C:A1:13
```

## 公钥 / 证书
需要导出证书时执行（在 android/ 目录下）：
```bash
keytool -exportcert -alias airmoney -keystore app/upload-keystore.jks -storepass airmoney2025 -rfc -file airmoney.cer
```

## Keystore 信息
- 路径: `android/app/upload-keystore.jks`
- Alias: `airmoney`
- 密码: `airmoney2025` （**请自行修改并妥善保管**）
- 有效期: 约 27 年 (至 2053 年)

## 安全提醒
- 已添加 `*.jks` 和 `key.properties` 到 .gitignore，**切勿提交到 Git**
- 建议将 keystore 备份到安全位置
- 上线前请修改 keystore 密码

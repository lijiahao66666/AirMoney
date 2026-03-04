# AirMoney（哎呀钱）

在意你的每一笔钱。

基于 Flutter 开发的消费管理 App，主打买前咨询、买后记账与分析反思。

## 产品方案

详见 [docs/PRODUCT_DESIGN.md](docs/PRODUCT_DESIGN.md)

## UI 设计

详见 [docs/UI_DESIGN.md](docs/UI_DESIGN.md)

## 技术栈

- **客户端**：Flutter
- **本地存储**：SQLite
- **后端**：Node.js（API 代理，调用腾讯混元）
- **大模型**：腾讯混元

## 快速开始

### 1. 启动后端服务

```bash
cd server
cp .env.example .env   # 复制并填写 TENCENT_SECRET_ID、TENCENT_SECRET_KEY 等
node app.js
```

默认端口 9001，混元 API、积分、登录均在此服务中。

### 2. 运行 Flutter 应用

```bash
# 默认连接 localhost:9001
flutter run

# 或指定 API 地址
flutter run --dart-define=AIRMONEY_API_PROXY_URL=http://your-server:9001 --dart-define=AIRMONEY_API_KEY=your_key
```

### 3. 复用 AirRead 后端（可选）

若已部署 AirRead 后端，可将 `AIRMONEY_API_PROXY_URL` 指向同一地址，混元代理与积分体系通用。

## 模块说明

| 模块 | 依赖 | 说明 |
|------|------|------|
| 记账 | 无 | 本地 SQLite，不依赖网络 |
| 分析 | 混元 + 积分 | 单次分析（记完一笔）、周期分析 |
| 咨询 | 混元 + 积分 | 买前对话，输入「我想买 XX」 |
| 积分 / 登录 | 后端 | 参考 AirRead 的积分与登录逻辑 |

## 项目结构

```
lib/
├── core/theme/      # 主题与色彩
├── data/            # 数据库与模型
├── services/        # API、认证、分析、咨询
├── presentation/    # 页面与 Provider
└── main.dart
server/              # Node.js 后端
docs/                # 产品设计、UI 设计
```

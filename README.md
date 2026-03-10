# AirMoney（哎呀钱）

AirMoney 是一款智能个人财务管理应用，主打“买前咨询、买后记账与分析反思”。它帮助用户理性消费，清晰掌握财务状况。

## 项目结构

本项目采用统一的结构设计：

- **client/**: Flutter 客户端源代码。
- **server/**: Node.js 后端服务。
- **scripts/**: 构建和部署脚本。
- **docs/**: 产品设计 (PRODUCT_DESIGN.md)、UI 设计 (UI_DESIGN.md) 和部署文档。

## 技术栈

- **客户端**: Flutter
  - 状态管理: `provider`
  - 数据库: `sqflite` (本地存储)
  - 提醒: `flutter_local_notifications`, `timezone`
  - UI: `flutter_slidable`
- **服务端**: Node.js
- **部署**: 宝塔面板

## 部署指南

### Web 端部署

1. 运行构建脚本：
   ```powershell
   ./scripts/build_web_release.ps1
   ```
2. 将构建产物上传至云服务器宝塔面板的 HTML 站点目录。
3. 访问域名：[money.air-inc.top](https://money.air-inc.top)

### 服务端部署

1. 将 `server/` 目录上传至服务器。
2. 在服务器上运行 `npm install` 安装依赖。
3. 使用 PM2 启动服务。

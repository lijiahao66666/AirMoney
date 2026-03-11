# AirMoney（哎呀钱）

AirMoney 是一款以买前咨询、买后反思为核心理念的个人理财与记账应用。客户端聚焦记账、分析与 AI 咨询，服务端提供混元大模型代理、积分系统与短信登录能力。

## 功能概览

- 记账与分类：日常收支记录、分类统计、筛选与查询。
- AI 咨询（该不该花）：分析用户购买意图，结合近 30 天同类支出给出建议。
- AI 消费分析：对单笔与周期账单生成简短分析与反思建议。
- 账单提醒：支持多时段提醒与本地通知。
- 积分系统：显示积分余额与消费情况。

## 客户端功能细节

- 咨询服务：调用混元 ChatCompletions，支持流式输出与推理内容。
- 消费分析：提供单笔与周期分析提示词生成。
- 提醒系统：本地通知 + 多时间段提醒配置。

## 服务端功能

- 代理腾讯云混元 API（ChatCompletions），服务端完成签名。
- 本地积分计费与用户数据存储。
- 远程配置接口 `/config`。
- 短信验证码登录与鉴权。

## 目录结构

- client/：Flutter 客户端
- server/：Node.js 服务端
- scripts/：构建与部署脚本
- README.md：项目说明

## 本地运行

客户端：
```
cd client
flutter pub get
flutter run
```

服务端：
```
cd server
npm install
node app.js
```

## Deployment

- Web build: run `scripts/build_web_release.ps1`.
- Output: `client/build/web/` and `airmoney-web.zip` in repo root.
- Web deploy: upload the zip or `client/build/web/` to your static HTML site.
- Server deploy: upload `server/`, run `npm install`, then `pm2 start app.js --name airmoney`.
- Config: edit `scripts/build_config.ps1` before building.

## 参考

项目规范请查看 `product_rule.md`。

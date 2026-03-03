# GitHub 仓库创建与推送说明

当前项目已初始化 Flutter 和 git，需在 GitHub 上先创建仓库后再推送。

## 步骤

### 1. 在 GitHub 创建新仓库

1. 打开 https://github.com/new
2. **Repository name** 填写：`AirMoney`
3. **Description**（可选）：在意你的每一笔钱。买前咨询、买后记账与分析反思。
4. 选择 **Private** 或 **Public**
5. **不要**勾选 "Add a README file"
6. 点击 **Create repository**

### 2. 推送本地代码

在项目根目录执行：

```bash
cd C:\Users\28679\traeProjects\AirMoney
git push -u origin main
```

若 GitHub 显示的是 `master` 作为默认分支，可改用：

```bash
git branch -M master
git push -u origin master
```

### 3. 如使用 SSH

若你偏好 SSH，可修改远程地址：

```bash
git remote set-url origin git@github.com:lijiahao66666/AirMoney.git
git push -u origin main
```

（请将 `lijiahao66666` 替换为你的 GitHub 用户名）

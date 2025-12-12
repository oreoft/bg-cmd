# bgs - Bilibili Goods CLI

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/oreoft/bg-cmd)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

**bgs** (bilibili goods) 是一个用于 B站会员购商城的命令行工具，支持批量上架和批量购买商品。

## ✨ 功能特性

- 🔐 **扫码登录** - 使用 Bilibili App 扫码快速登录
- 📦 **批量上架** - 一键将库存中的商品批量上架到市场
- 🛒 **批量购买** - 批量购买市场商品，生成支付宝付款码
- 💰 **灵活定价** - 支持固定价格和随机价格区间
- 🔄 **自动刷新** - Cookie 过期自动刷新，无需重复登录

## 📋 系统要求

- macOS 或 Linux
- Bash 4.0+
- 以下依赖工具：
  - `curl` - HTTP 请求
  - `jq` - JSON 解析
  - `openssl` - Cookie 刷新加密
  - `qrencode` - 二维码生成

## 🚀 安装

### Homebrew 安装 (推荐)

```bash
brew tap oreoft/tap
brew install bg-cmd
```

### 手动安装

```bash
# 克隆仓库
git clone https://github.com/oreoft/bg-cmd.git
cd bg-cmd

# 安装依赖
brew install jq qrencode

# 添加到 PATH
export PATH="$PWD/bin:$PATH"

# 或创建软链接
ln -s "$PWD/bin/bgs" /usr/local/bin/bgs
```

## 📖 使用指南

### 1. 登录

首次使用需要登录，使用 Bilibili App 扫码：

```bash
bgs auth login
```

终端会显示二维码，使用手机 B站 App 扫码确认登录。

### 2. 查看登录状态

```bash
bgs auth status
```

### 3. 配置价格

上架商品前，先设置你的价格：

```bash
# 设置固定价格（单位：元）
bgs config publish.price 200

# 设置随机价格区间（100-300元之间随机）
bgs config publish.price [100,300]

# 查看当前配置
bgs config publish.price

# 查看所有配置
bgs config --list
```

> ⚠️ 实际上架价格 = min(你的价格, 商品最高限价)

### 4. 批量上架商品

将库存中的所有商品上架到市场：

```bash
# 正式上架
bgs publish

# 预览模式（不实际上架，只显示会做什么）
bgs publish --dry-run
```

### 5. 批量购买商品

```bash
# 交互模式 - 提示输入商品ID
bgs buy

# 命令行指定商品ID
bgs buy 183955612413,183960137592

# 数组格式
bgs buy [183955612413,183960137592]
```

购买流程：
1. 查询商品详情（名称、价格）
2. 创建订单
3. 生成支付宝付款链接和二维码
4. 等待支付完成后继续下一个商品

## 🔧 命令参考

```
bgs <command> [options]

Commands:
  auth        认证管理
    login     扫码登录
    logout    退出登录
    status    查看登录状态
    refresh   强制刷新 Cookie

  publish     批量上架库存商品
    --dry-run 预览模式

  buy         批量购买商品
    [ids]     商品ID列表

  config      配置管理
    <key>           获取配置
    <key> <value>   设置配置
    --list          列出所有配置
    --unset <key>   删除配置

  help        显示帮助
  version     显示版本
```

## 📁 配置目录

所有配置和认证信息存储在 `~/.bg-cmd/` 目录：

```
~/.bg-cmd/
├── auth        # 登录凭证（自动生成）
└── config      # 用户配置
```

## 🐛 调试模式

遇到问题时，可开启调试模式查看详细日志：

```bash
BG_DEBUG=1 bgs publish
```

## ❓ 常见问题

### Q: 二维码无法显示？

确保已安装 `qrencode`：
```bash
brew install qrencode
```

### Q: 提示 Cookie 过期？

Cookie 会自动刷新，如果仍然失败，尝试重新登录：
```bash
bgs auth login
```

### Q: macOS 上 openssl 加密失败？

macOS 自带的 LibreSSL 功能有限，建议安装 Homebrew 版本：
```bash
brew install openssl
```

### Q: 上架失败提示价格过高？

商品有最高限价，实际上架价格会自动取 min(你的价格, 商品最高限价)。

## 📄 License

MIT License - 详见 [LICENSE](LICENSE) 文件

## 🙏 致谢

- [bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect) - Bilibili API 文档


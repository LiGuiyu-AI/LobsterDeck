# LobsterDeck 🦞

桂鱼的 AI 原生中枢。原有的报告台、文件站、Agent 看板继续独立运行；本仓库新增一个 **只读数据服务** 和一个 **原生 SwiftUI iOS App**，把三处的内容统一成一套橙色主题的 Liquid Glass 体验。

- App 不套网页：列表、文件、Agent 时间线全部原生绘制。
- 报告正文保留每篇 HTML 自己的排版与配色，只在外面包一层统一的原生阅读壳。
- 首页模块与尺寸由 Agent 决策（服务端 JSON），App 只负责渲染。

```
┌────────────┐   ┌────────────┐   ┌────────────┐
│ Reports    │   │ File inbox │   │ Lobster    │
│ *.html     │   │ 目录/文件   │   │ Context git│
└─────┬──────┘   └─────┬──────┘   └─────┬──────┘
      └────────────┬───┴────────────────┘
                   ▼
          server/app.py  (stdlib, read-only)
                   ▼  JSON + Bearer
          ios/  SwiftUI · iOS 26 · Liquid Glass
```

## 目录

| 路径 | 作用 |
|---|---|
| `server/app.py` | 单文件 Python 服务（无第三方依赖），只读聚合 + 报告 token 管理 |
| `server/update_home.py` | 给 Agent 用的首页布局上传脚本 |
| `ios/project.yml` | XcodeGen 工程定义（不提交 .xcodeproj） |
| `ios/LobsterDeck/` | SwiftUI 源码 |
| `.github/workflows/ios.yml` | macOS runner 构建未签名 IPA |
| `deploy/` | systemd 用户服务与安装脚本 |

## 数据服务

```bash
LOBSTERDECK_PORT=3320 python3 server/app.py
# 首次启动会在 /vol1/1000/Docker/LobsterDeck/token.txt 生成访问令牌
```

### 接口

所有 `/api/v1/*`（除 health）都需要 `Authorization: Bearer <token>`。

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/v1/health` | 健康检查，无需鉴权 |
| GET | `/api/v1/overview` | 首页：统计 + 已解析的模块 |
| GET/PUT | `/api/v1/home/layout` | 首页布局 JSON |
| GET | `/api/v1/reports` | 报告列表（标题/日期/是否共享） |
| GET | `/api/v1/reports/{id}/html` | 单篇 HTML（资源链接已重写到代理） |
| GET | `/api/v1/report-assets/{path}` | 报告站静态资源 |
| GET/POST | `/api/v1/reports/tokens` | 查询 / share·rotate·revoke |
| GET | `/api/v1/files?path=` | 目录浏览 |
| GET | `/api/v1/files/recent` | 最近文件（带首次发现时间） |
| GET | `/api/v1/files/raw?path=` | 下载原文件 |
| GET | `/api/v1/agents` | Agent 概览 |
| GET | `/api/v1/agents/{agent}/commits` | 该 Agent 的记忆提交 |
| GET | `/api/v1/agents/commit?sha=` | 单次提交与 diff |

### 首页布局

`modules[]` 每项支持：

- `kind`: `hero` · `list` · `agents` · `actions`
- `size`: `small`（半宽）· `medium`/`large`/`hero`（整宽）
- `source`: `reports` · `files` · `agents`
- `limit`: 列表条数
- `title` / `subtitle` / `accent`

示例：

```json
{
  "version": 1,
  "generated_by": "lobster",
  "modules": [
    {"id":"hero","kind":"hero","size":"hero","title":"晚上好，桂鱼","subtitle":"今天也辛苦了。"},
    {"id":"r","kind":"list","size":"large","title":"最新报告","source":"reports","limit":3},
    {"id":"f","kind":"list","size":"medium","title":"新文件","source":"files","limit":4},
    {"id":"a","kind":"agents","size":"large","title":"Agent 动态","source":"agents","limit":3}
  ]
}
```

Agent 侧更新：

```bash
LOBSTERDECK_URL=https://deck.example.com LOBSTERDECK_TOKEN=... \
  python3 server/update_home.py layout.json
```

## iOS

- 最低 iOS 26（使用 Liquid Glass：`glassEffect` / `GlassEffectContainer` / `.glass` 按钮）
- 无需付费开发者账号：不使用 Push、App Groups、Associated Domains 等付费能力
- 首次打开填写服务地址 + 令牌，令牌存 Keychain

### 构建

GitHub Actions（`macos-26`，Xcode 26）自动产出 **未签名 IPA**：

```
Actions → iOS Build → Artifacts → LobsterDeck-unsigned-ipa
```

本地构建（需要 Mac）：

```bash
brew install xcodegen
cd ios && xcodegen generate
open LobsterDeck.xcodeproj
```

## 部署服务

```bash
bash deploy/install.sh
systemctl --user status lobsterdeck
```

服务只读取：`Reports/site`、`file-inbox`、`LobsterContext` 的 git 历史。
唯一的写操作是报告 token 表（与报告台 `/admin/` 完全相同的机制）。

## 设计约定

- 主色：`#FF7A18` → `#E8500A`
- 卡片：Liquid Glass，圆角 26，橙色淡染
- 动效：`smooth` 曲线，列表数字用 `numericText` 过渡
- 报告正文：不改样式，只重写资源路径

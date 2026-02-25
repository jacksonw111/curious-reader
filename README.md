# Curious Reader

Curious Reader 是一个面向 macOS 的本地电子书阅读器，定位为「快打开、稳翻页、可长时间阅读」。

当前聚焦本地阅读体验（PDF / EPUB / MOBI 导入），不依赖账号体系或云端服务。

## 功能概览

- 格式支持
  - `PDF`：基于 `PDFKit`
  - `EPUB`：当前为本地解包 + OPF 解析 + WebKit 渲染
  - `MOBI`：按兼容导入处理，转换后走 EPUB 阅读链路
- 书库
  - 展示全部导入书籍
  - 顶部「最近阅读」最多 5 本（按阅读时间统计）
  - 列表/卡片视图切换、搜索、分页
- 阅读器
  - 目录（TOC）导航与当前章节高亮
  - EPUB 目录树支持章节展开/收起
  - 记忆阅读进度，重新打开自动恢复
  - 书签管理
- 检索
  - 阅读态搜索弹窗（modal），点击结果可跳转
- AI 翻译（可选）
  - 划词后显示「翻译」操作入口，点击才触发翻译
  - OpenRouter API Key 配置后，自动使用免费模型
  - 翻译流式输出，结果持久化，后续 hover 可直接查看
- 截图
  - 选中文本后可截图预览并保存到本地

## 技术架构

项目按模块拆分（Swift Package）：

- `ReaderCore`：领域模型、格式探测、统一协议
- `ReaderPDF`：PDF 引擎适配
- `ReaderEPUB`：EPUB 解析与会话
- `ReaderMOBI`：MOBI 转换编排
- `ReaderLibrary`：本地书库与持久化
- `CuriousReaderApp`：SwiftUI / AppKit UI 组合层

关键依赖：

- `ZIPFoundation`（EPUB 解包）

## 环境要求

- macOS 14+
- Xcode 16+（建议）
- Swift 6.2（与 `Package.swift` 对齐）

## 本地开发

### 1. 拉起工程依赖并编译

```bash
swift build
```

### 2. 运行测试

```bash
swift test --parallel
```

### 3. 生成测试 HTML 报告

```bash
./scripts/generate-test-report.sh
```

报告输出：

- `dist/test-report/index.html`

### 4. 打包 macOS App

```bash
./scripts/package-app.sh
```

输出：

- `dist/CuriousReader.app`

### 5. 生成 DMG

```bash
./scripts/create-dmg.sh
```

输出：

- `dist/CuriousReader.dmg`

## GitHub Release 自动构建

仓库已配置 GitHub Actions 工作流：

- 工作流文件：`.github/workflows/release-macos.yml`
- 触发方式：
  - 推送 `main`：自动生成/更新 `main-latest` 预发布（滚动快照）
  - 推送标签：`v*`（例如 `v0.2.0`）
  - 手动触发：`workflow_dispatch`（输入 tag）
- 执行内容：
  - 运行 `swift test --parallel`
  - 构建 `CuriousReader.app`
  - 生成 `CuriousReader.dmg`
  - 上传到对应 GitHub Release（`*.app.zip` + `*.dmg`）

常用发布命令：

```bash
git tag v0.2.0
git push origin v0.2.0
```

## 配置说明

- 阅读偏好与翻译缓存默认保存在用户 `Application Support/CuriousReader` 下
- OpenRouter API Key 使用系统 Keychain 存储，不写入仓库文件

## 隐私与安全

- 默认不上传书籍内容
- 无显式授权不采集遥测
- 导入失败会区分权限/损坏/不支持格式并给出可解释提示

## 当前约束与后续演进

- Readium Swift Toolkit 在纯 macOS 原生接入上仍有平台限制
- 当前 EPUB 路线是本地解析 + WebKit 渲染，保留后续切换 Readium 的适配空间

## 目录结构

```text
.
├── Sources/
│   ├── CuriousReaderApp/
│   ├── ReaderCore/
│   ├── ReaderEPUB/
│   ├── ReaderLibrary/
│   ├── ReaderMOBI/
│   └── ReaderPDF/
├── Tests/
├── scripts/
├── logo/
└── AGENTS.md
```

## 工程规范（摘要）

- Swift 6 严格并发
- 阻塞 I/O 与解析必须后台执行
- 修复 bug 必须带回归测试
- 关键改动需跑测试并验证打包产物

详细规范见：

- [`AGENTS.md`](./AGENTS.md)

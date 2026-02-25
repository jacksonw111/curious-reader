# Curious Reader Engineering Guide

更新日期：2026-02-25（美国）

## 1. 产品目标与范围
- 平台：macOS（原生应用，Apple Silicon 优先）。
- 阅读格式：`PDF`、`EPUB`、`MOBI`。
- 核心体验：打开快、翻页稳、检索准、长时间阅读不疲劳。
- 非目标（MVP 阶段）：云同步、账号体系、在线书城。

## 2. 技术路线（强制）
### 2.1 格式引擎
- PDF：使用 `PDFKit`（Apple 原生）。
- EPUB：使用 `Readium Swift Toolkit` 作为阅读与解析核心。
- MOBI：按“兼容导入格式”处理，不做自研渲染内核。导入后转换为 EPUB 再统一进入 Readium 流程。

### 2.2 为什么这样选
- Apple 官方持续维护 PDFKit，并在近年更新中强化 Live Text、表单、改进缩放与性能问题。
- Readium 在 iOS/macOS 上提供成熟的 EPUB/PDF/A11y 能力与导航组件。
- Amazon KDP 已在 2025-03-18 起停止接受 MOBI 新提交，MOBI 是遗留格式，工程上应以“转换兼容”而非“深度投入”处理。

### 2.3 当前实现约束（2026-02-24）
- `readium/swift-toolkit` 官方 Swift 包当前平台声明以 iOS 为主；纯 macOS 原生目标接入会受限。
- 因此当前 macOS MVP 策略为：
  - EPUB：本地解包 + OPF 解析 + WebKit 渲染（已落地）
  - 保持 `ReaderEPUB` 适配层，后续可切换到 Readium（如 Catalyst 路线或官方新增 macOS 支持）

## 3. 架构原则
### 3.1 App 形态
- 采用文档式应用（`NSDocument` / `DocumentGroup` 思路）：
  - 每本书是一个文档会话，可多窗口并行阅读。
  - 使用系统文档生命周期与自动保存能力。

### 3.2 模块边界（必须）
- `ReaderCore`：领域模型、格式探测、阅读状态、协议定义。
- `ReaderPDF`：PDFKit 适配与缓存策略。
- `ReaderEPUB`：Readium 适配与导航封装。
- `ReaderMOBI`：MOBI 检测、元数据提取、转换编排（到 EPUB）。
- `ReaderLibrary`：本地书库、索引、持久化。
- `ReaderApp`：SwiftUI/AppKit UI 组合层。

禁止 UI 层直接访问底层解析细节；必须经过 `ReaderCore` 定义的协议。

## 4. 代码规范（必须执行）
### 4.1 Swift 与并发
- Swift 版本：`Swift 6`，开启严格并发检查。
- 所有可能阻塞主线程的 I/O、解析、索引必须放到后台任务。
- `@MainActor` 仅用于 UI 状态提交，不用于重计算。
- 每个 async 入口必须支持取消（`Task.isCancelled` 检查）。

### 4.2 结构与可维护性
- 单文件建议 < 400 行；超出需拆分。
- 复杂类型优先协议化（`protocol + implementation`），便于替换引擎和写测试。
- 禁止“巨型 ViewModel”：单个 ViewModel 建议 < 12 个公开方法。
- 错误处理统一使用领域错误：
  - `ReaderError.formatUnsupported`
  - `ReaderError.parseFailed`
  - `ReaderError.permissionDenied`
  - `ReaderError.corruptedFile`

### 4.3 测试规范
- `ReaderCore` 目标覆盖率 >= 80%。
- 每个格式至少有：
  - 1 个“正常打开”用例
  - 1 个“损坏文件”用例
  - 1 个“超大文件性能烟测”用例
- 修复 bug 必须附带回归测试。

## 5. 性能优化基线
### 5.1 启动与打开
- 冷启动目标：< 1.5s（P95，开发机基线）。
- 打开 300MB PDF 或 1000 章 EPUB：
  - 首屏渲染目标 < 800ms（已缓存场景）
  - 未缓存场景 < 2.0s（P95）

### 5.2 渲染与内存
- 只渲染可视区与邻近页（前后预取窗口默认 2 页，可动态调参）。
- 缩略图与分页信息必须缓存（内存 + 磁盘两级）。
- 大文档搜索使用后台索引，禁止主线程全文扫描。
- 内存警戒线（MVP）：常驻 < 600MB；触发阈值时主动降级缓存。

### 5.3 仪表化（必须）
- 关键路径加 `os_signpost`：导入、解析、首屏、翻页、全文检索。
- 每次性能改动必须跑 Instruments（Time Profiler + Hangs + Allocations）并记录前后对比。
- 出现卡顿先查“主线程占用 > 16ms 的连续区间”。

## 6. 界面设计原则（macOS）
### 6.1 桌面交互一致性
- 遵循 macOS 文档应用习惯：菜单栏命令、工具栏、侧边栏、分栏布局。
- 首选系统交互控件与快捷键语义，不发明“反平台”操作。
- 支持多窗口并行阅读（研究/对照场景）。

### 6.2 阅读体验
- 提供稳态阅读模式：
  - 主题（浅色/护眼/深色）
  - 字体与行高调节（EPUB）
  - 页边距与段间距微调
- 导航层级统一：目录、书签、标注、搜索结果使用一致的信息架构。
- 所有动画优先“短、轻、可取消”；禁止炫技动画干扰阅读。

### 6.3 可访问性（必须）
- 全部核心操作可键盘完成。
- VoiceOver 朗读顺序正确，控件有明确标签。
- 颜色对比满足 WCAG AA。
- 阅读进度、章节位置、搜索结果数量要有可访问语义描述。

## 7. 安全与隐私
- 默认开启 App Sandbox 能力设计；文件访问使用 security-scoped bookmarks 持久化授权。
- 不上传用户书籍内容；无明确授权不做遥测。
- 导入失败提示需可解释（权限、损坏、格式不支持分别提示）。

## 8. 开发流程与质量门禁
- 分支策略：`main` 受保护，功能走短分支 + PR。
- 提交信息：`type(scope): summary`（示例：`feat(epub): add publication loader`）。
- PR 必须包含：
  - 变更说明
  - 风险点
  - 测试证据（单测/性能对比/截图）
- 合并前必须通过：
  - 编译
  - 单测
  - 基础性能烟测
  - 可访问性清单检查
- 每次实现更新完成后必须重新生成交付物：
  - `./scripts/package-app.sh`
  - `./scripts/create-dmg.sh`
  - 确认产物位于 `dist/CuriousReader.app` 与 `dist/CuriousReader.dmg`

## 9. MVP 迭代顺序（执行顺序）
1. 工程骨架与模块拆分。
2. 本地导入 + 格式探测。
3. PDF 阅读 MVP（翻页/缩放/搜索）。
4. EPUB 阅读 MVP（目录/样式/进度）。
5. MOBI 导入转换链路。
6. 统一书库、书签与阅读进度。
7. 性能与可访问性专项收敛。

## 10. 关键参考（研究来源）
- Apple: What’s new in PDFKit (WWDC22)  
  https://developer.apple.com/videos/play/wwdc2022/10089/
- Apple: Build document-based apps in SwiftUI (WWDC20)  
  https://developer.apple.com/videos/play/wwdc2020/10039/
- Apple: Analyze hangs with Instruments (WWDC23)  
  https://developer.apple.com/videos/play/wwdc2023/10248/
- Apple: Demystify SwiftUI performance (WWDC23)  
  https://developer.apple.com/videos/play/wwdc2023/10160/
- Readium Swift Toolkit（官方仓库）  
  https://github.com/readium/swift-toolkit
- Readium 3.3.0 / 3.7.0 发布说明（a11y 与性能相关）  
  https://github.com/readium/swift-toolkit/releases/tag/3.3.0  
  https://github.com/readium/swift-toolkit/releases/tag/3.7.0
- W3C EPUB 3.3（Recommendation，2026-01-13）  
  https://www.w3.org/TR/epub-33/
- W3C EPUB Reading Systems 1.1（Candidate Recommendation Draft，2026-02-09）  
  https://www.w3.org/TR/epub-rs-11/
- Amazon KDP：MOBI 提交终止公告（2025-03-18 生效）  
  https://kdp.amazon.com/en_US/help/topic/G200634390
- libmobi（MOBI 解析/转换相关开源库）  
  https://github.com/bfabiszewski/libmobi

## 11. GitHub 开发生命周期规范（代理行为标准，强制）
### 11.1 分支与集成策略
- 采用 GitHub Flow：`main` 始终保持可发布。
- 功能/修复必须从 `main` 拉短分支，命名规范：
  - `feat/<area>-<topic>`
  - `fix/<area>-<topic>`
  - `chore/<topic>`
- 除发布紧急修复外，禁止直接向 `main` 提交未评审代码。

### 11.2 提交规范
- 提交必须小步、可回滚、语义单一（一次提交只做一件事）。
- 提交信息固定为 `type(scope): summary`，例如：
  - `feat(library): add recent reading shelf`
  - `fix(epub): make toc chapter nodes collapsible`
- 代码变更必须同步更新文档/测试（如适用）。

### 11.3 PR 与质量门禁
- 每个分支通过 PR 合并；PR 描述必须包含：
  - 背景与目标
  - 变更清单
  - 风险与回滚方案
  - 测试证据（命令输出、截图、报告）
- 合并前必须通过：
  - `swift test --parallel`
  - 打包验收：`./scripts/package-app.sh` + `./scripts/create-dmg.sh`
  - 关键功能手测（阅读、目录、搜索、翻译、截图）

### 11.4 发布策略（SemVer）
- 版本号采用 `vMAJOR.MINOR.PATCH`（例如 `v0.1.0`）。
- 正式发布只允许从 `main` 打 tag：
  1. `git checkout main`
  2. `git pull --ff-only`
  3. `git tag vX.Y.Z`
  4. `git push origin vX.Y.Z`
- CI 工作流自动构建并上传 `*.app.zip` 与 `*.dmg` 到 GitHub Release。
- `main` push 自动更新 `main-latest` 预发布，tag 发布生成正式版本。

### 11.5 安全与敏感信息防护
- 提交前必须执行敏感扫描，禁止上传：
  - API Key / Token / 私钥 / 证书 / `.env` / 本地缓存数据
- API Key 只存 Keychain（本项目为 OpenRouter Keychain Store）。
- 二进制产物不入库（`dist/` 由 `.gitignore` 排除）。

### 11.6 `gh` CLI 标准操作（默认执行路径）
- 查看仓库状态：`gh repo view`
- 创建 PR：`gh pr create`
- 查看 CI：`gh run list` / `gh run watch`
- 查看 Release：`gh release list` / `gh release view <tag>`
- 代理在具备权限与上下文时，默认使用 `gh` 完成生命周期操作并回传结果。

### 11.7 GitHub 实践参考
- GitHub Docs: About pull requests  
  https://docs.github.com/articles/about-pull-requests
- GitHub Docs: About protected branches  
  https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches
- GitHub Docs: About code owners  
  https://docs.github.com/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners
- GitHub Docs: About releases  
  https://docs.github.com/repositories/releasing-projects-on-github/about-releases
- GitHub Docs: About secret scanning  
  https://docs.github.com/code-security/secret-scanning/about-secret-scanning
- SemVer  
  https://semver.org/

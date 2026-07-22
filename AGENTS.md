# AGENTS.md — dual-sub-merge

给在本仓库工作的 AI 编码助手与协作者的约定。改代码前先读此文件。

## 项目是什么

Flutter 桌面应用：把**中文单语字幕 + 外文单语字幕**合并为 `.chs+eng.ass`（Aegisub）。  
不把中英压成同一条 Dialogue；清洗文本、统一四套 HDRipad 样式；可选删致谢；视频抽轨在独立「视频处理」页。

## 技术栈

- Flutter 3 / Dart 3，Material 3，界面中文  
- 依赖：`file_picker`、`path`、`path_provider`、`shared_preferences`、`collection`  
- 字幕解析/写出：**纯 Dart**，不引入重型原生字幕库  
- 外部进程：`mkvmerge` / `mkvextract`、`ffmpeg` / `ffprobe`（仅抽轨）

## 目录约定

| 路径 | 职责 |
|------|------|
| `lib/models/` | 数据模型，少放逻辑 |
| `lib/services/parse/` | ASS/SRT/VTT 读写 |
| `lib/services/text_pipeline.dart` | 文本清洗、斜体、样式名 |
| `lib/services/blacklist.dart` | 致谢正则 |
| `lib/services/bilingual_inline.dart` | 行内/单行双语检测 |
| `lib/services/bilingual_split.dart` | `\N` 双语拆成中/外 |
| `lib/services/bilingual_convert_service.dart` | 双语文件 → `.chs+eng.ass` |
| `lib/services/language_from_name.dart` | 文件名语言 token、前缀归一化、`hasTrailingLanguageTag` |
| `lib/services/language_tag_rename_service.dart` | 无标记字幕移入 chs-sub/eng-sub |
| `lib/services/file_matcher.dart` | 目录扫描与分组（含 extract / chs-sub / eng-sub） |
| `lib/services/merge_service.dart` | 端到端编排；尊重 `selectedPrefixes`；可选改名 |
| `lib/services/extract/` | 容器轨探测与抽取 |
| `lib/ui/` | 页面；重逻辑放 services |
| `test/` | 单测；清洗/黑名单/双语/解析必测 |

## 业务规则（勿随意改语义）

1. **语言**：文件名标记优先（`chs`/`eng` 等）；无标记才内容多数表决。整文件角色，避免「中文里偶发英文」翻盘。  
2. **`\N`/真实换行** → 空格；输出 Dialogue 不得含裸换行。  
3. **标签**：去掉 ASS override 与多余 HTML；**保留** `{\i1}`/`{\i0}`/`{\i}`。  
4. **HTML 斜体**：`<i>`/`<em>` → `{\i1}` / `{\i0}`（在 `text_pipeline`）。  
5. **样式优先级**：Lyric > annotation(`\an8`) > 中下 / 英上。  
6. **黑名单**：仅 `removeCredits == true` 时生效；默认规则用**锚定正则**，防误删对白。  
7. **双语成品（`\N` 上下中英）**：扫描为 `GroupKind.bilingualFile`（UI：**样式转换**），可转换则拆成双轨写出 `.chs+eng.ass`（保留源）；无法可靠拆分则跳过并汇总。无 `\N` 的单行混排不切开。  
8. **勾选**：扫描后默认 `selected = true`；合并只处理勾选项（`MergeService.selectedPrefixes`）。  
9. **抽轨**：仅「视频处理」页 `MergeService.extractOnly`；中文 chs；外文 eng → 无则 sdh → 再无 Prompt。字幕合并页不抽轨。跳过 PGS/VobSub。  
10. **输出**：`{displayPrefix}.chs+eng.ass`，默认 PlayRes 1920×1080。写出目录由 `OutputDirMode` 决定：默认 `输入/dual-sub-merged/`（合并时不存在则创建）；可选源文件夹或自定义路径（自定义时快捷勾选变灰）。扫描/抽轨仍用输入目录。  
11. **拖拽**：输入/输出灰色 `DropTarget` 卡片；输入：目录/字幕/视频并扫描（不自动合并）；输出：仅目录→custom。  
11b. **界面字体**：`UiFontSettings`（系统族名或字体文件），主题统一 `FontWeight.w400`。  
11c. **导航**：左侧 `NavigationRail` — 字幕处理 / 视频处理。  
12. **列表清空**：仅清扫描分组，不重置输入/输出路径设置。  
13. **标记语言改名**（`tagLanguageOnMerge`，默认 false）：仅无尾部语言标记且角色已识别的中/外源字幕；**移动**到 `chs-sub/`、`eng-sub/`，文件名插入 `.chs`/`.eng`。扫描需包含这两子目录。双语源不改名。提供「仅改名」与「改名并合并」。  
14. **列表 UI**：每组中在上、外在下；kind 带图标与 ⓘ tooltip（配对 / 样式转换 / 视频）。

## 代码风格

- **不要**无请求地加注释  
- 匹配现有命名与结构；新逻辑优先纯函数 + 单测  
- UI 文案保持中文  
- 不要提交密钥；不要 `git commit` 除非用户明确要求  

## 常用命令

```powershell
flutter pub get
flutter test
flutter analyze
flutter run -d windows
.\build_desktop.ps1          # 一键 release（默认 --no-pub，不测、不 analyze）
.\build_desktop.ps1 -PubGet -Open
```

Windows 产物：`build\windows\x64\runner\Release\dual_sub_merge.exe`（发布带上整个 Release 目录）。

## 改动检查清单

- [ ] `flutter test` 通过  
- [ ] `flutter analyze` 无 error  
- [ ] 若动 `text_pipeline` / 黑名单 / 双语检测：补或更新 `test/pipeline_test.dart`  
- [ ] 若动配对/合并：考虑冒烟 `test/smoke_merge_test.dart`（依赖本地临时样例时可跳过）  
- [ ] 用户可见行为变化时更新 `README.md`  

## 明确不要做

- 写 exploit / 攻击脚本  
- 默认开启破坏性覆盖以外的静默删源文件  
- 在移动端强依赖 mkvextract（抽轨以桌面为主）  
- 无 `\N` 的单行中英混排强行切开（除非产品明确扩展）  

## 相关文档

- 用户说明：`README.md`  
- 构建：`build_desktop.ps1` / `build_desktop.bat`

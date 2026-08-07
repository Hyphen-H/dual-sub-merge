# dual-sub-merge

中文 + 外文**单语字幕**一键合并为 Aegisub 可用的双语 ASS（`.chs+eng.ass`）。

面向字幕整理 / 压制流程：清洗文本、统一 HDRipad 样式、可选删致谢、可选从 MKV/MP4 抽内嵌轨。

---

## 功能一览

| 能力 | 说明 |
|------|------|
| 批量输入 | 可选择文件夹或任意多个字幕文件，按**文件名前缀**自动配对中/外轨；重叠来源自动去重 |
| 输出目录 | 默认 `输入/dual-sub-merged/`；可快捷选源文件夹，或自选/拖入输出路径 |
| 路径拖放 | 输入/输出为独立落点卡片，拖入时高亮反馈；输入支持文件夹/字幕/视频 |
| 勾选处理 | 扫描后**默认全选**，可取消勾选跳过部分条目；支持清空列表 |
| 标记语言改名 | 可选：无尾部语言标记的源字幕**移动**到 `chs-sub/`、`eng-sub/`，文件名加 `.chs`/`.eng`；可「仅改名」或「改名并合并」 |
| 格式 | 输入 `ass` / `ssa` / `srt` / `vtt`（UTF-8、UTF-16LE/BE）；输出 ASS |
| 清洗 | `\N`/换行→空格；去特效与位置标签；**保留斜体** |
| HTML 斜体 | SRT 的 `<i>` / `<em>` → `{\i1}` / `{\i0}` |
| 标点 | 全角→半角；引号规范化；`中文,中文` → `中文, 中文` |
| 样式 | `中下HDRipad` / `英上HDRipad` / `annotationHDRipad` / `LyricHDRipad` |
| 样式来源 | 内置默认、多行粘贴、从 ASS 勾选导入 |
| 删除致谢 | 开关 + 正则黑名单（默认锚定「翻译:」等致谢行） |
| `\N` 样式转换 | 上下中英成品拆成双轨，统一 HDRipad 样式写出 `.chs+eng.ass`（保留源文件） |
| 工作台 | 专业桌面侧栏：**字幕处理** / **视频处理**，样式、黑名单和设置集中在底部 |
| 拖拽 | 支持拖入**文件夹 / 字幕 / 视频**（仅扫描勾选，不自动合并） |
| 视频抽轨 | 在「视频处理」页支持拖入单个/多个 MKV、MP4 或目录；逐个视频串行抽取，进度条显示当前视频实时进度；PGS/VobSub 等图像字幕仅展示、不勾选 |
| 分辨率 | 默认 1080p，可选 720p / 1440p / 4K |

### 界面与交互

- 桌面工作台采用侧栏 + 主内容区布局，字幕处理与视频处理保持一致的操作层级。
- 侧栏导航为 macOS 风格浅色选中/悬停填充（无 Material 涟漪），避免 Windows 上透明 Ink 整行变黑。
- 输入与输出路径、处理选项、主操作、任务列表和运行详情按工作流程自上而下排列。
- 输出分辨率用精简下拉（触发器显示 1080p 等档位，菜单可带像素），高度与筛选芯片一致，收起悬停微蓝，切换即保存。
- 任务列表使用类型与状态徽标；缺轨/冲突等标黄色「需检查」，可点徽标仅显示需检查项；中文文件始终在外文上方。
- 视频任务卡直接列出容器中的全部字幕轨、语言、标题、编码与默认/强制/SDH 标记；可逐轨勾选需要抽取的字幕。
- 运行详情默认收起，扫描、合并和抽轨进度在主操作区即时反馈；需要时可展开查看完整日志。
- 1280×720 为推荐窗口尺寸，较窄桌面窗口会自动收紧侧栏与间距。

### 样式优先级

1. `LyricHDRipad` — 首尾 `*` 或含 ♪♫ 等  
2. `annotationHDRipad` — 源含 `\an8`  
3. 中文轨 → `中下HDRipad`  
4. 外文轨 → `英上HDRipad`  

### 文件名语言标记（优先）

中文：`chs` `cht` `zh` `cn` `chi` …  
外文：`eng` `en` `sdh` `jpn` `kor` …  

无标记时回退内容多数表决。输出名：`{公共前缀}.chs+eng.ass`。

可选 **标记语言改名**：仅处理文件名尾部尚无语言 token 的字幕；按识别结果移入：

```text
输入/chs-sub/{原名}.chs.srt
输入/eng-sub/{原名}.eng.srt
```

已有 `chs`/`eng` 等标记的文件不会改动。

---

## 环境要求

- **Flutter** 3.x（桌面端）+ 对应平台桌面支持  
  - Windows：Visual Studio Build Tools（含“使用 C++ 的桌面开发”）  
- 仅合并外挂字幕时**不必**装抽轨工具  
- 从视频抽字幕时：  
  - [MKVToolNix](https://mkvtoolnix.download/)（`mkvmerge` / `mkvextract`）  
  - [ffmpeg](https://ffmpeg.org/)（含 `ffprobe`）  

```powershell
# 示例（Windows + scoop）
scoop bucket add extras
scoop install extras/flutter
scoop install ffmpeg
# MKVToolNix 建议官网安装到 Program Files
```

---

## 一键构建（推荐）

双击或在项目根目录执行：

```powershell
.\build_desktop.bat
# 或
.\build_desktop.ps1
```

| 参数 | 含义 |
|------|------|
| （默认） | `flutter build --release --no-pub`（依赖已就绪时跳过 pub get，更快） |
| `-PubGet` | 强制先 `flutter pub get`（改过 `pubspec` 时用） |
| `-Open` | 成功后打开输出目录 |
| `-NoLaunch` | 成功后不提示启动 |
| `-Platform windows\|macos\|linux` | 目标桌面平台 |
| `-VerboseFlutter` | 详细构建日志 |

**Windows 产物：**

```text
build\windows\x64\runner\Release\dual_sub_merge.exe
```

发布时请拷贝 **整个 `Release` 文件夹**（含 `dll` 与 `data`），不要只复制 exe。

---

## 开发运行

```powershell
flutter pub get
flutter run -d windows
flutter test
flutter analyze
```

---

## 使用流程

1. 打开应用 → 选择**字幕文件**或**字幕输入文件夹**（内含成对的中/外字幕；支持多选与拖入）
2. 确认**输出目录**（默认 `输入文件夹/dual-sub-merged/`，通过输出模式菜单切换源文件夹或自定义路径）
3. 查看列表（每组：**中** 在上、**外** 在下；配对 / 样式转换 / 视频 带图标与 ⓘ 说明）→ 默认全选；**清空**仅清列表  
4. 按需打开 **删除致谢** / **标记语言改名**  
5. 设置分辨率；字幕样式、黑名单和工具设置位于左侧栏底部
6. **开始合并**（若启用标记语言则为 **改名并合并**）→ 在输出目录生成 `.chs+eng.ass`  
7. 需要从容器抽轨时：左侧切到 **视频处理** → 选择视频输入文件夹，或直接拖入单个/多个视频文件（与字幕输入独立保存，互不影响）→ 在每个视频卡片中勾选需要的字幕轨 → **开始抽轨**（逐个视频串行处理，顶部进度条显示当前视频实时进度）→ 再回字幕处理合并

将文件夹、字幕或视频**拖到「输入」卡片**；输出文件夹拖到「输出」卡片。字幕与视频两个输入卡片各自记忆目录，拖入或选择其中一个不会改变另一个。设置中可改界面字体。

抽轨文件默认写到视频所在目录下 `dual-sub-merge-extract/`（可在设置中改名）。中文、英文轨分别使用 `chs`、`eng` 标记；同语言多轨会附加轨道编号，避免互相覆盖。

---

## 项目结构

```text
lib/
  main.dart                 # 入口
  models/                   # cue / 样式 / 选项 / 匹配组
  services/
    parse/                  # ASS·SRT·VTT 解析与 ASS 写出
    text_pipeline.dart      # 清洗与样式判定
    blacklist.dart          # 致谢正则
    bilingual_inline.dart   # 行内/单行双语检测
    language_from_name.dart # 文件名语言与前缀
    file_matcher.dart       # 目录扫描配对
    merge_service.dart      # 总编排
    extract/                # mkv/ffmpeg 抽轨
    tools/                  # 外部工具路径解析
    app_settings.dart       # 本地设置持久化
  ui/                       # 中文界面与统一 design system
test/                       # 单元测试与冒烟
build_desktop.ps1 / .bat    # 一键构建
AGENTS.md                   # 给 AI / 协作者的约定
```

---

## 配置说明

设置与黑名单、样式通过 `shared_preferences` 持久化。

**默认致谢正则**（仅「删除致谢」开启时生效）锚定整行，例如：

```regex
^\s*翻译\s*[:：]\s*\S.*$
^\s*本字幕仅供爱好者交流[，,]\s*严禁用于任何商业途径\s*$
```

默认规则用行首锚定，避免误伤对白里的「翻译」等词。  
支持占位符 `$中文字符` → 一段汉字。

---

## 已知限制（v1）

- 不对中外时间轴强制对齐；双轨独立 Dialogue  
- 双语拆分目前仅支持 **`\N` / 换行上下中英**；无换行的单行中英混排不切开  
- 不 OCR 图像字幕（PGS / VobSub）  
- 容器抽轨以**桌面**为主  

---

## License

Private / 按仓库约定使用。

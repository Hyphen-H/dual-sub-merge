# dual-sub-merge

中文 + 外文**单语字幕**一键合并为 Aegisub 可用的双语 ASS（`.chs+eng.ass`）。

面向字幕整理 / 压制流程：清洗文本、统一 HDRipad 样式、可选删致谢、可选从 MKV/MP4 抽内嵌轨。

---

## 功能一览

| 能力 | 说明 |
|------|------|
| 文件夹批量 | 同一**输入**目录内按**文件名前缀**自动配对中/外轨 |
| 输出目录 | 默认 `输入/dual-sub-merged/`；可快捷选源文件夹，或自选/拖入输出路径 |
| 路径拖放 | 输入/输出为灰色落点卡片，可分别拖入；输入支持文件夹/字幕/视频 |
| 勾选处理 | 扫描后**默认全选**，可取消勾选跳过部分条目；支持清空列表 |
| 标记语言改名 | 可选：无尾部语言标记的源字幕**移动**到 `chs-sub/`、`eng-sub/`，文件名加 `.chs`/`.eng`；可「仅改名」或「改名并合并」 |
| 格式 | 输入 `ass` / `ssa` / `srt` / `vtt`；输出 ASS |
| 清洗 | `\N`/换行→空格；去特效与位置标签；**保留斜体** |
| HTML 斜体 | SRT 的 `<i>` / `<em>` → `{\i1}` / `{\i0}` |
| 标点 | 全角→半角；引号规范化；`中文,中文` → `中文, 中文` |
| 样式 | `中下HDRipad` / `英上HDRipad` / `annotationHDRipad` / `LyricHDRipad` |
| 样式来源 | 内置默认、多行粘贴、从 ASS 勾选导入 |
| 删除致谢 | 开关 + 正则黑名单（默认锚定「翻译:」等致谢行） |
| `\N` 样式转换 | 上下中英成品拆成双轨，统一 HDRipad 样式写出 `.chs+eng.ass`（保留源文件） |
| 双页 | 左侧导航：**字幕处理** / **视频处理** |
| 拖拽 | 支持拖入**文件夹 / 字幕 / 视频**（仅扫描勾选，不自动合并） |
| 视频抽轨 | 在「视频处理」页：MKV `mkvextract` / MP4 `ffmpeg`；eng 无则 SDH |
| 分辨率 | 默认 1080p，可选 720p / 1440p / 4K |

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

1. 打开应用 → **选择输入文件夹**（内含成对的中/外字幕，或 mkv/mp4；支持拖入）  
2. 确认**输出目录**（默认 `输入文件夹/dual-sub-merged/`，可勾选源文件夹或自选路径）  
3. 查看列表（每组：**中** 在上、**外** 在下；配对 / 样式转换 / 视频 带图标与 ⓘ 说明）→ 默认全选；**清空**仅清列表  
4. 按需打开 **删除致谢** / **标记语言改名**  
5. 设置分辨率与样式（菜单图标）  
6. **开始合并**（若启用标记语言则为 **改名并合并**）→ 在输出目录生成 `.chs+eng.ass`  
7. 需要从容器抽轨时：左侧切到 **视频处理** → 勾选 → **开始抽轨** → 再回字幕处理合并  

将文件夹、字幕或视频**拖到「输入」卡片**；输出文件夹拖到「输出」卡片。设置中可改界面字体。

抽轨文件默认写到输入目录下 `dual-sub-merge-extract/`（可在设置中改名）。

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
  ui/                       # 中文界面
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

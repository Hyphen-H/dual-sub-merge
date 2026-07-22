import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../main.dart';
import '../models/merge_options.dart';
import '../services/app_settings.dart';
import '../services/tools/tool_resolver.dart';
import '../services/ui_font.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.options, required this.onChanged});

  final MergeOptions options;
  final ValueChanged<MergeOptions> onChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _mkv;
  late final TextEditingController _ffmpeg;
  late final TextEditingController _ffprobe;
  late final TextEditingController _extractDir;
  late final TextEditingController _fontFamily;
  UiFontSettings _font = const UiFontSettings();
  String _toolStatus = '';

  @override
  void initState() {
    super.initState();
    _mkv = TextEditingController(text: widget.options.mkvToolNixDir);
    _ffmpeg = TextEditingController(text: widget.options.ffmpegPath);
    _ffprobe = TextEditingController(text: widget.options.ffprobePath);
    _extractDir = TextEditingController(text: widget.options.extractSubdir);
    _fontFamily = TextEditingController();
    _loadFont();
    _detect();
  }

  Future<void> _loadFont() async {
    final f = DualSubMergeApp.of(context)?.uiFont ?? await AppSettings.loadUiFont();
    if (!mounted) return;
    setState(() {
      _font = f;
      _fontFamily.text = f.family;
    });
  }

  @override
  void dispose() {
    _mkv.dispose();
    _ffmpeg.dispose();
    _ffprobe.dispose();
    _extractDir.dispose();
    _fontFamily.dispose();
    super.dispose();
  }

  Future<void> _detect() async {
    final t = await ToolResolver.resolve(
      mkvToolNixDir: _mkv.text,
      ffmpegPath: _ffmpeg.text,
      ffprobePath: _ffprobe.text,
    );
    setState(() {
      _toolStatus = [
        'mkvmerge: ${t.mkvmerge ?? "未找到"}',
        'mkvextract: ${t.mkvextract ?? "未找到"}',
        'ffmpeg: ${t.ffmpeg ?? "未找到"}',
        'ffprobe: ${t.ffprobe ?? "未找到"}',
      ].join('\n');
    });
  }

  Future<void> _applyFont(UiFontSettings font) async {
    final app = DualSubMergeApp.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _font = font;
      _fontFamily.text = font.family;
    });
    await AppSettings.saveUiFont(font);
    await app?.applyUiFont(font);
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('界面字体已更新')),
    );
  }

  Future<void> _pickFontFile() async {
    final r = await FilePicker.pickFiles(
      dialogTitle: '选择字体文件',
      type: FileType.custom,
      allowedExtensions: const ['ttf', 'otf', 'ttc'],
    );
    if (r == null || r.files.isEmpty) return;
    final path = r.files.single.path;
    if (path == null || path.isEmpty) return;
    await _applyFont(_font.copyWith(filePath: path, family: ''));
  }

  void _save() {
    widget.options.mkvToolNixDir = _mkv.text.trim();
    widget.options.ffmpegPath = _ffmpeg.text.trim();
    widget.options.ffprobePath = _ffprobe.text.trim();
    widget.options.extractSubdir = _extractDir.text.trim().isEmpty
        ? 'dual-sub-merge-extract'
        : _extractDir.text.trim();
    widget.onChanged(widget.options);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('设置已保存')));
    _detect();
  }

  @override
  Widget build(BuildContext context) {
    final body = Theme.of(context).textTheme.bodyMedium;
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: [
          FilledButton(onPressed: _save, child: const Text('保存')),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('界面字体', style: body),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in UiFontSettings.presets)
                FilterChip(
                  label: Text(preset.$1),
                  selected: _font.filePath.isEmpty && _font.family == preset.$2,
                  onSelected: (_) => _applyFont(
                    UiFontSettings(family: preset.$2, filePath: ''),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _fontFamily,
                  decoration: const InputDecoration(
                    labelText: '系统字体族名',
                    hintText: '例如 Microsoft YaHei',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (v) => _applyFont(
                    UiFontSettings(family: v.trim(), filePath: ''),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _applyFont(
                  UiFontSettings(family: _fontFamily.text.trim(), filePath: ''),
                ),
                child: const Text('应用族名'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  _font.filePath.isEmpty
                      ? '未选择字体文件'
                      : '字体文件：${p.basename(_font.filePath)}',
                  style: body,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              OutlinedButton.icon(
                onPressed: _pickFontFile,
                icon: const Icon(Icons.font_download_outlined),
                label: const Text('选择字体文件'),
              ),
              if (_font.filePath.isNotEmpty) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => _applyFont(
                    UiFontSettings(family: _fontFamily.text.trim(), filePath: ''),
                  ),
                  child: const Text('清除文件'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '预览：中外字幕合并 dual-sub-merge 0123456789',
            style: body?.copyWith(fontSize: 16),
          ),
          const Divider(height: 32),
          TextField(
            controller: _mkv,
            decoration: const InputDecoration(
              labelText: 'MKVToolNix 目录',
              hintText: r'C:\Program Files\MKVToolNix',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ffmpeg,
            decoration: const InputDecoration(
              labelText: 'ffmpeg 路径（可空=自动查找）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ffprobe,
            decoration: const InputDecoration(
              labelText: 'ffprobe 路径（可空=自动查找）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _extractDir,
            decoration: const InputDecoration(
              labelText: '抽轨输出子目录名',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('覆盖已存在的 .chs+eng.ass'),
            value: widget.options.overwrite,
            onChanged: (v) => setState(() => widget.options.overwrite = v),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _detect,
            icon: const Icon(Icons.search),
            label: const Text('检测工具'),
          ),
          const SizedBox(height: 12),
          SelectableText(_toolStatus, style: const TextStyle(fontFamily: 'Consolas')),
          const SizedBox(height: 16),
          Text(
            '提示：未找到 ffmpeg 时，可用 scoop install ffmpeg，或将 ffmpeg.exe 加入 PATH。'
            ' MKV 抽取需要 MKVToolNix。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

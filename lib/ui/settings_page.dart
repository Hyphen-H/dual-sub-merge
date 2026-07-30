import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../main.dart';
import '../models/merge_options.dart';
import '../services/app_settings.dart';
import '../services/tools/tool_resolver.dart';
import '../services/ui_font.dart';
import 'design_system.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.options,
    required this.onChanged,
  });

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
  Map<String, String> _toolStatus = const {};
  bool _detecting = false;

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
    final f =
        DualSubMergeApp.of(context)?.uiFont ?? await AppSettings.loadUiFont();
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
    setState(() => _detecting = true);
    final t = await ToolResolver.resolve(
      mkvToolNixDir: _mkv.text,
      ffmpegPath: _ffmpeg.text,
      ffprobePath: _ffprobe.text,
    );
    if (!mounted) return;
    setState(() {
      _detecting = false;
      _toolStatus = {
        'mkvmerge': t.mkvmerge ?? '',
        'mkvextract': t.mkvextract ?? '',
        'ffmpeg': t.ffmpeg ?? '',
        'ffprobe': t.ffprobe ?? '',
      };
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
    messenger.showSnackBar(const SnackBar(content: Text('界面字体已更新')));
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('设置已保存')));
    _detect();
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: '设置',
      description: '配置界面字体、外部工具和文件处理行为。',
      actions: [
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined, size: 17),
          label: const Text('保存设置'),
        ),
      ],
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              AppSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionHeader(
                      title: '界面字体',
                      description: '选择系统字体族或载入本地字体文件；所有界面文字保持常规字重。',
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final preset in UiFontSettings.presets)
                          FilterChip(
                            label: Text(preset.$1),
                            selected:
                                _font.filePath.isEmpty &&
                                _font.family == preset.$2,
                            onSelected: (_) =>
                                _applyFont(UiFontSettings(family: preset.$2)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final narrow = constraints.maxWidth < 680;
                        final field = TextField(
                          controller: _fontFamily,
                          decoration: const InputDecoration(
                            labelText: '系统字体族名',
                            hintText: '例如 Microsoft YaHei UI',
                            isDense: true,
                          ),
                          onSubmitted: (v) =>
                              _applyFont(UiFontSettings(family: v.trim())),
                        );
                        final action = OutlinedButton(
                          onPressed: () => _applyFont(
                            UiFontSettings(family: _fontFamily.text.trim()),
                          ),
                          child: const Text('应用族名'),
                        );
                        return narrow
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  field,
                                  const SizedBox(height: 8),
                                  action,
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(child: field),
                                  const SizedBox(width: 8),
                                  action,
                                ],
                              );
                      },
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: UiTokens.subtle,
                        border: Border.all(color: UiTokens.border),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.font_download_outlined,
                            size: 19,
                            color: UiTokens.muted,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _font.filePath.isEmpty
                                  ? '未选择字体文件'
                                  : p.basename(_font.filePath),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          OutlinedButton(
                            onPressed: _pickFontFile,
                            child: const Text('选择文件'),
                          ),
                          if (_font.filePath.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () => _applyFont(
                                UiFontSettings(family: _fontFamily.text.trim()),
                              ),
                              child: const Text('清除'),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        '预览：中外字幕合并 dual-sub-merge 0123456789',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionHeader(
                      title: '外部工具',
                      description: '留空时自动从系统 PATH 和常见安装位置查找。',
                      trailing: OutlinedButton.icon(
                        onPressed: _detecting ? null : _detect,
                        icon: _detecting
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.search_rounded, size: 17),
                        label: Text(_detecting ? '检测中' : '重新检测'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _mkv,
                      decoration: const InputDecoration(
                        labelText: 'MKVToolNix 目录',
                        hintText: r'C:\Program Files\MKVToolNix',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _ffmpeg,
                      decoration: const InputDecoration(
                        labelText: 'ffmpeg 可执行文件路径',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _ffprobe,
                      decoration: const InputDecoration(
                        labelText: 'ffprobe 可执行文件路径',
                      ),
                    ),
                    const SizedBox(height: 14),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: UiTokens.border),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Column(
                        children: [
                          for (
                            var i = 0;
                            i < _toolStatus.entries.length;
                            i++
                          ) ...[
                            _ToolStatusRow(
                              entry: _toolStatus.entries.elementAt(i),
                            ),
                            if (i < _toolStatus.length - 1)
                              const Divider(indent: 14, endIndent: 14),
                          ],
                          if (_toolStatus.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(14),
                              child: Text('正在检测工具…'),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '未找到 ffmpeg 时可使用 scoop install ffmpeg，或将可执行文件加入 PATH；MKV 抽取需要 MKVToolNix。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionHeader(
                      title: '文件处理',
                      description: '设置抽轨目录与已存在输出文件的处理方式。',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _extractDir,
                      decoration: const InputDecoration(labelText: '抽轨输出子目录名'),
                    ),
                    const SizedBox(height: 12),
                    Material(
                      color: UiTokens.subtle,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                        side: const BorderSide(color: UiTokens.border),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 2,
                        ),
                        title: const Text('覆盖已存在的 .chs+eng.ass'),
                        subtitle: const Text('关闭时将跳过已经存在的同名输出文件。'),
                        value: widget.options.overwrite,
                        onChanged: (v) =>
                            setState(() => widget.options.overwrite = v),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolStatusRow extends StatelessWidget {
  const _ToolStatusRow({required this.entry});

  final MapEntry<String, String> entry;

  @override
  Widget build(BuildContext context) {
    final found = entry.value.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(
            found
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
            size: 18,
            color: found
                ? UiTokens.success
                : Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 10),
          SizedBox(width: 90, child: Text(entry.key)),
          Expanded(
            child: Text(
              found ? entry.value : '未找到',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: found
                    ? UiTokens.muted
                    : Theme.of(context).colorScheme.error,
                fontFamily: found ? 'Consolas' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

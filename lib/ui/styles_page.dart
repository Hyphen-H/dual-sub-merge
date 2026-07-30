import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/ass_style.dart';
import '../models/merge_options.dart';
import '../services/parse/ass_parser.dart';
import 'design_system.dart';

class StylesPage extends StatefulWidget {
  const StylesPage({super.key, required this.options, required this.onChanged});

  final MergeOptions options;
  final ValueChanged<MergeOptions> onChanged;

  @override
  State<StylesPage> createState() => _StylesPageState();
}

class _StylesPageState extends State<StylesPage> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.options.styleLines.join('\n'),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final lines = _controller.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    widget.options.styleLines = lines;
    widget.onChanged(widget.options);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已保存 ${lines.length} 条字幕样式')));
  }

  void _restore() {
    _controller.text = StyleCatalog.defaultStyleLines.join('\n');
    setState(() {});
  }

  Future<void> _importAss() async {
    final r = await FilePicker.pickFiles(
      dialogTitle: '选择 ASS / SSA 样式来源',
      type: FileType.custom,
      allowedExtensions: ['ass', 'ssa'],
    );
    if (r == null || r.files.single.path == null) return;
    final doc = await AssParser.parseFile(File(r.files.single.path!));
    if (doc.styles.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('所选文件中未找到 Style')));
      }
      return;
    }
    if (!mounted) return;
    final selected = await showDialog<List<AssStyle>>(
      context: context,
      builder: (ctx) => _StylePickDialog(styles: doc.styles),
    );
    if (selected == null || selected.isEmpty) return;
    final existing = _controller.text.trim();
    final add = selected.map((e) => e.line).join('\n');
    _controller.text = existing.isEmpty ? add : '$existing\n$add';
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final lineCount = _controller.text
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .length;
    return AppPageScaffold(
      title: '字幕样式',
      description: '管理输出 ASS 使用的 HDRipad 样式定义。',
      actions: [
        OutlinedButton.icon(
          onPressed: _importAss,
          icon: const Icon(Icons.file_upload_outlined, size: 17),
          label: const Text('从 ASS 导入'),
        ),
        const SizedBox(width: 8),
        TextButton(onPressed: _restore, child: const Text('恢复默认')),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined, size: 17),
          label: const Text('保存'),
        ),
      ],
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSurface(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: const [
                      _StyleRoleBadge(
                        icon: Icons.translate,
                        label: '中文',
                        name: StyleCatalog.chinese,
                      ),
                      _StyleRoleBadge(
                        icon: Icons.language,
                        label: '外文',
                        name: StyleCatalog.foreign,
                      ),
                      _StyleRoleBadge(
                        icon: Icons.vertical_align_top,
                        label: '顶部注释',
                        name: StyleCatalog.annotation,
                      ),
                      _StyleRoleBadge(
                        icon: Icons.music_note_outlined,
                        label: '歌词',
                        name: StyleCatalog.lyric,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: AppSurface(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                          child: SectionHeader(
                            title: 'Style 定义',
                            description: '每行一条标准 “Style:” 定义，保存后用于所有新输出文件。',
                            trailing: StatusBadge(
                              label: '$lineCount 条',
                              foreground: UiTokens.muted,
                              background: const Color(0xFFF0F3F7),
                            ),
                          ),
                        ),
                        const Divider(),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            onChanged: (_) => setState(() {}),
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            style: const TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 12,
                              height: 1.5,
                            ),
                            decoration: const InputDecoration(
                              filled: true,
                              fillColor: Color(0xFFFCFDFE),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.all(16),
                              hintText: 'Style: HDRipad,Arial,58,...',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StyleRoleBadge extends StatelessWidget {
  const _StyleRoleBadge({
    required this.icon,
    required this.label,
    required this.name,
  });

  final IconData icon;
  final String label;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: UiTokens.subtle,
        border: Border.all(color: UiTokens.border),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 2),
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StylePickDialog extends StatefulWidget {
  const _StylePickDialog({required this.styles});
  final List<AssStyle> styles;

  @override
  State<_StylePickDialog> createState() => _StylePickDialogState();
}

class _StylePickDialogState extends State<_StylePickDialog> {
  late final Set<String> _picked;

  @override
  void initState() {
    super.initState();
    _picked = widget.styles.map((e) => e.name).where((n) {
      return n == StyleCatalog.chinese ||
          n == StyleCatalog.foreign ||
          n == StyleCatalog.annotation ||
          n == StyleCatalog.lyric;
    }).toSet();
    if (_picked.isEmpty) _picked.addAll(widget.styles.map((e) => e.name));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择要导入的样式'),
      content: SizedBox(
        width: 560,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '已自动勾选与四套输出样式同名的项目，可在导入前调整。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: UiTokens.border),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: ListView.separated(
                  itemCount: widget.styles.length,
                  separatorBuilder: (_, _) =>
                      const Divider(indent: 12, endIndent: 12),
                  itemBuilder: (context, index) {
                    final style = widget.styles[index];
                    return CheckboxListTile(
                      value: _picked.contains(style.name),
                      title: Text(style.name),
                      subtitle: Text(
                        style.line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _picked.add(style.name);
                          } else {
                            _picked.remove(style.name);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _picked.isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  widget.styles.where((s) => _picked.contains(s.name)).toList(),
                ),
          child: Text('导入 ${_picked.length} 项'),
        ),
      ],
    );
  }
}

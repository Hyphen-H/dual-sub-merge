import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/ass_style.dart';
import '../models/merge_options.dart';
import '../services/parse/ass_parser.dart';

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
    _controller = TextEditingController(text: widget.options.styleLines.join('\n'));
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
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('样式已保存')));
  }

  void _restore() {
    _controller.text = StyleCatalog.defaultStyleLines.join('\n');
    setState(() {});
  }

  Future<void> _importAss() async {
    final r = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ass', 'ssa'],
    );
    if (r == null || r.files.single.path == null) return;
    final doc = await AssParser.parseFile(File(r.files.single.path!));
    if (doc.styles.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未找到 Style')));
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('字幕样式'),
        actions: [
          TextButton(onPressed: _importAss, child: const Text('从 ASS 导入')),
          TextButton(onPressed: _restore, child: const Text('恢复默认')),
          FilledButton(onPressed: _save, child: const Text('保存')),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '粘贴标准 Style: 行。输出会使用名称：'
              '${StyleCatalog.chinese} / ${StyleCatalog.foreign} / '
              '${StyleCatalog.annotation} / ${StyleCatalog.lyric}',
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ),
          ],
        ),
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
    if (_picked.isEmpty) {
      _picked.addAll(widget.styles.map((e) => e.name));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择要导入的样式'),
      content: SizedBox(
        width: 480,
        height: 360,
        child: ListView(
          children: widget.styles.map((s) {
            return CheckboxListTile(
              value: _picked.contains(s.name),
              title: Text(s.name),
              subtitle: Text(s.line, maxLines: 1, overflow: TextOverflow.ellipsis),
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _picked.add(s.name);
                  } else {
                    _picked.remove(s.name);
                  }
                });
              },
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final list = widget.styles.where((s) => _picked.contains(s.name)).toList();
            Navigator.pop(context, list);
          },
          child: const Text('导入'),
        ),
      ],
    );
  }
}

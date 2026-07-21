import 'package:flutter/material.dart';

import '../models/merge_options.dart';
import '../services/blacklist.dart';

class BlacklistPage extends StatefulWidget {
  const BlacklistPage({super.key, required this.options, required this.onChanged});

  final MergeOptions options;
  final ValueChanged<MergeOptions> onChanged;

  @override
  State<BlacklistPage> createState() => _BlacklistPageState();
}

class _BlacklistPageState extends State<BlacklistPage> {
  late final TextEditingController _controller;
  List<String> _invalid = [];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.options.blacklistRules.join('\n'));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final rules = _controller.text.split('\n');
    _invalid = BlacklistFilter.validateRules(rules);
    widget.options.blacklistRules = rules.where((e) => e.trim().isNotEmpty).toList();
    widget.onChanged(widget.options);
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _invalid.isEmpty ? '已保存黑名单规则' : '已保存，但有 ${_invalid.length} 条无效正则',
        ),
      ),
    );
  }

  void _restore() {
    _controller.text = MergeOptions.defaultBlacklistRules.join('\n');
    setState(() => _invalid = []);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('致谢黑名单（正则）'),
        actions: [
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
              '仅在主页开启「删除致谢」时生效。一行一条正则，匹配去标签后的整行文本则删除该条字幕。'
              r' 可用占位符 $中文字符 表示一段汉字。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 13),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: r'^\s*翻译\s*[:：]\s*\S.*$',
                ),
              ),
            ),
            if (_invalid.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '无效正则:\n${_invalid.join('\n')}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

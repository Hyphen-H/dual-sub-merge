import 'package:flutter/material.dart';

import '../models/merge_options.dart';
import '../services/blacklist.dart';
import 'design_system.dart';

class BlacklistPage extends StatefulWidget {
  const BlacklistPage({
    super.key,
    required this.options,
    required this.onChanged,
  });

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
    _controller = TextEditingController(
      text: widget.options.blacklistRules.join('\n'),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _validate() {
    setState(
      () => _invalid = BlacklistFilter.validateRules(
        _controller.text.split('\n'),
      ),
    );
  }

  void _save() {
    final rules = _controller.text.split('\n');
    _invalid = BlacklistFilter.validateRules(rules);
    widget.options.blacklistRules = rules
        .where((e) => e.trim().isNotEmpty)
        .toList();
    widget.onChanged(widget.options);
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _invalid.isEmpty
              ? '已保存 ${widget.options.blacklistRules.length} 条黑名单规则'
              : '已保存，但有 ${_invalid.length} 条无效正则',
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
    final count = _controller.text
        .split('\n')
        .where((e) => e.trim().isNotEmpty)
        .length;
    return AppPageScaffold(
      title: '致谢黑名单',
      description: '使用锚定正则过滤字幕中的制作、翻译与发布致谢。',
      actions: [
        TextButton(onPressed: _restore, child: const Text('恢复默认')),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _validate,
          icon: const Icon(Icons.rule_outlined, size: 17),
          label: const Text('校验'),
        ),
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
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(
                          Icons.info_outline,
                          size: 19,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '仅在字幕处理页开启“删除致谢”时生效。每行一条正则，匹配去标签后的整行文本才会删除；'
                          r'可用占位符 $中文字符 表示一段汉字。',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
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
                            title: '正则规则',
                            description: r'建议使用 ^ 与 $ 锚定整行，避免误删正常对白。',
                            trailing: StatusBadge(
                              label: '$count 条',
                              foreground: UiTokens.muted,
                              background: const Color(0xFFF0F3F7),
                            ),
                          ),
                        ),
                        const Divider(),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            onChanged: (_) => setState(() => _invalid = []),
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            style: const TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 13,
                              height: 1.55,
                            ),
                            decoration: const InputDecoration(
                              filled: true,
                              fillColor: Color(0xFFFCFDFE),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.all(16),
                              hintText: r'^\s*翻译\s*[:：]\s*\S.*$',
                            ),
                          ),
                        ),
                        if (_invalid.isNotEmpty) ...[
                          const Divider(),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 130),
                            color: Theme.of(context).colorScheme.errorContainer
                                .withValues(alpha: 0.55),
                            padding: const EdgeInsets.all(12),
                            child: SingleChildScrollView(
                              child: Text(
                                '发现 ${_invalid.length} 条无效正则：\n${_invalid.join('\n')}',
                                style: TextStyle(
                                  fontFamily: 'Consolas',
                                  fontSize: 12,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ),
                        ],
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

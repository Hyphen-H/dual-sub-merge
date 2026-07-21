import 'package:flutter/material.dart';

import '../models/merge_options.dart';
import '../services/tools/tool_resolver.dart';

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
  String _toolStatus = '';

  @override
  void initState() {
    super.initState();
    _mkv = TextEditingController(text: widget.options.mkvToolNixDir);
    _ffmpeg = TextEditingController(text: widget.options.ffmpegPath);
    _ffprobe = TextEditingController(text: widget.options.ffprobePath);
    _extractDir = TextEditingController(text: widget.options.extractSubdir);
    _detect();
  }

  @override
  void dispose() {
    _mkv.dispose();
    _ffmpeg.dispose();
    _ffprobe.dispose();
    _extractDir.dispose();
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
          SwitchListTile(
            title: const Text('拖入后自动开始处理'),
            subtitle: const Text('关闭时仅扫描并勾选，需手动点「开始合并」'),
            value: widget.options.dragAutoRun,
            onChanged: (v) => setState(() => widget.options.dragAutoRun = v),
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

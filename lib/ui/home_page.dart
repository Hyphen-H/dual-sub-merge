import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/match_group.dart';
import '../models/merge_options.dart';
import '../models/track_role.dart';
import '../services/app_settings.dart';
import '../services/extract/extract_service.dart';
import '../services/extract/track_info.dart';
import '../services/extract/track_selector.dart';
import '../services/file_matcher.dart';
import '../services/language_tag_rename_service.dart';
import '../services/merge_service.dart';
import '../services/parse/subtitle_loader.dart';
import 'blacklist_page.dart';
import 'settings_page.dart';
import 'styles_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  MergeOptions _options = MergeOptions();
  String? _dir;
  List<MatchGroup> _groups = [];
  final _log = StringBuffer();
  bool _busy = false;
  bool _dragging = false;
  String _progress = '';
  int _resIndex = 1; // 1080p
  static final _videoExts = {'.mkv', '.mp4'};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final opts = await AppSettings.loadOptions();
    final last = await AppSettings.loadLastDir();
    setState(() {
      _options = opts;
      _dir = last;
      _resIndex = ResolutionPreset.list.indexWhere(
        (e) => e.width == opts.playResX && e.height == opts.playResY,
      );
      if (_resIndex < 0) _resIndex = 1;
    });
    if (last != null && Directory(last).existsSync()) {
      await _scan();
    }
  }

  Future<void> _persist() => AppSettings.saveOptions(_options);

  Future<void> _pickDir() async {
    final path = await FilePicker.getDirectoryPath(dialogTitle: '选择输入文件夹');
    if (path == null) return;
    setState(() => _dir = path);
    await AppSettings.saveLastDir(path);
    await _scan();
  }

  Future<void> _pickOutputDir() async {
    final path = await FilePicker.getDirectoryPath(dialogTitle: '选择输出文件夹');
    if (path == null) return;
    setState(() {
      _options.outputDirMode = OutputDirMode.custom;
      _options.customOutputDir = path;
    });
    await _persist();
  }

  void _setOutputMode(OutputDirMode mode) {
    setState(() => _options.outputDirMode = mode);
    _persist();
  }

  String? _resolvedOutputDir() {
    switch (_options.outputDirMode) {
      case OutputDirMode.source:
        return _dir;
      case OutputDirMode.mergedSubdir:
        if (_dir == null) return null;
        return p.join(_dir!, MergeOptions.mergedSubdirName);
      case OutputDirMode.custom:
        final c = _options.customOutputDir.trim();
        return c.isEmpty ? null : c;
    }
  }

  String _outputDirLabel() {
    final path = _resolvedOutputDir();
    if (path != null) return path;
    return switch (_options.outputDirMode) {
      OutputDirMode.source => '未选择输入文件夹',
      OutputDirMode.mergedSubdir => '未选择输入文件夹（将使用 …/dual-sub-merged）',
      OutputDirMode.custom => '未指定输出文件夹',
    };
  }

  void _clearList() {
    setState(() => _groups = []);
  }

  Future<void> _scan({bool keepSelection = false}) async {
    if (_dir == null) return;
    final prevSelected = {
      for (final g in _groups) g.prefix: g.selected,
    };
    setState(() {
      _busy = true;
      _progress = '扫描中…';
    });
    try {
      final groups = await FileMatcher.scanDirectory(Directory(_dir!));
      for (final g in groups) {
        // default: all selected; preserve prior choice on refresh
        if (keepSelection && prevSelected.containsKey(g.prefix)) {
          g.selected = prevSelected[g.prefix]!;
        } else {
          g.selected = true;
        }
      }
      setState(() {
        _groups = groups;
        final n = _groups.where((e) => e.selected).length;
        _log.writeln('扫描 ${_groups.length} 组（默认全选 $n）@ $_dir');
      });
    } catch (e) {
      _log.writeln('扫描失败: $e');
    } finally {
      setState(() {
        _busy = false;
        _progress = '';
      });
    }
  }

  void _selectAll(bool value) {
    setState(() {
      for (final g in _groups) {
        g.selected = value;
      }
    });
  }

  Future<void> _renameOnly() async {
    if (_dir == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先选择输入文件夹')));
      return;
    }
    final selected = _groups.where((g) => g.selected).toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请至少勾选一组字幕')));
      return;
    }
    setState(() {
      _busy = true;
      _progress = '标记语言改名…';
    });
    try {
      final r = await LanguageTagRenameService().renameGroups(
        inputDir: Directory(_dir!),
        groups: selected,
        overwrite: _options.overwrite,
      );
      _log
        ..writeln('—— 仅改名 ——')
        ..writeln(r.logs.join('\n'))
        ..writeln('完成 ${r.renamedCount}，跳过 ${r.skippedCount}，失败 ${r.failCount}');
      await _scan(keepSelection: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '改名完成：${r.renamedCount} 个文件'
              '${r.failCount > 0 ? '，失败 ${r.failCount}' : ''}',
            ),
          ),
        );
      }
    } catch (e) {
      _log.writeln('改名失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('改名失败: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = '';
        });
      }
    }
  }

  Future<void> _run() async {
    if (_dir == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先选择输入文件夹')));
      return;
    }
    final outPath = _resolvedOutputDir();
    if (outPath == null || outPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先选择输出文件夹')));
      return;
    }
    final selected = _groups.where((g) => g.selected).map((g) => g.prefix).toSet();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请至少勾选一组字幕')));
      return;
    }
    final res = ResolutionPreset.list[_resIndex.clamp(0, ResolutionPreset.list.length - 1)];
    _options.playResX = res.width;
    _options.playResY = res.height;
    await _persist();

    setState(() {
      _busy = true;
      _progress = '处理中…';
    });

    final service = MergeService(
      options: _options,
      selectedPrefixes: selected,
      onProgress: (p) {
        if (!mounted) return;
        setState(() => _progress = '${p.message} (${p.current}/${p.total})');
      },
      onConflict: _resolveConflict,
      onPickTracks: _pickTracks,
    );

    try {
      final result = await service.run(
        Directory(_dir!),
        outputDir: Directory(outPath),
      );
      _log
        ..writeln('—— 完成 ——')
        ..writeln('成功 ${result.successCount} / 失败 ${result.failCount}')
        ..writeln('双语转换: ${result.convertedBilingual}')
        ..writeln('删除致谢行: ${result.removedCredits}')
        ..writeln(result.logs.join('\n'));
      if (result.skippedBilingual.isNotEmpty) {
        _log.writeln('双语无法转换已跳过:');
        for (final s in result.skippedBilingual) {
          _log.writeln('  - $s');
        }
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('部分双语无法转换'),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Text(result.skippedBilingual.join('\n')),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
              ],
            ),
          );
        }
      }
      await _scan(keepSelection: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '完成：成功 ${result.successCount}，失败 ${result.failCount}'
              '${result.convertedBilingual > 0 ? '，转换双语 ${result.convertedBilingual}' : ''}'
              '${result.skippedBilingual.isEmpty ? '' : '，跳过 ${result.skippedBilingual.length}'}',
            ),
          ),
        );
      }
    } catch (e) {
      _log.writeln('运行失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('失败: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = '';
        });
      }
    }
  }

  Future<bool> _resolveConflict(MatchGroup group) async {
    if (!mounted) return false;
    final files = <File>[
      if (group.chinese != null) group.chinese!.file,
      if (group.foreign != null) group.foreign!.file,
    ];
    // also list other unknown from message? keep simple: assign roles for two slots
    return await showDialog<bool>(
          context: context,
          builder: (ctx) {
            TrackRole? zhRole = group.chinese?.role;
            TrackRole? enRole = group.foreign?.role;
            File? zhFile = group.chinese?.file;
            File? enFile = group.foreign?.file;
            return StatefulBuilder(
              builder: (ctx, setLocal) {
                return AlertDialog(
                  title: Text('冲突: ${group.prefix}'),
                  content: SizedBox(
                    width: 420,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(group.message.isEmpty ? '请指定中/外字幕文件' : group.message),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<File>(
                          // ignore: deprecated_member_use
                          value: zhFile,
                          decoration: const InputDecoration(labelText: '中文字幕'),
                          items: files
                              .map(
                                (f) => DropdownMenuItem(
                                  value: f,
                                  child: Text(p.basename(f.path)),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setLocal(() => zhFile = v),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<File>(
                          // ignore: deprecated_member_use
                          value: enFile,
                          decoration: const InputDecoration(labelText: '外文字幕'),
                          items: files
                              .map(
                                (f) => DropdownMenuItem(
                                  value: f,
                                  child: Text(p.basename(f.path)),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setLocal(() => enFile = v),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('跳过')),
                    FilledButton(
                      onPressed: () {
                        if (zhFile != null) {
                          group.chinese = SubtitleFileRef(file: zhFile!, role: TrackRole.chinese);
                          zhRole = TrackRole.chinese;
                        }
                        if (enFile != null) {
                          group.foreign = SubtitleFileRef(file: enFile!, role: TrackRole.foreign);
                          enRole = TrackRole.foreign;
                        }
                        Navigator.pop(ctx, zhRole == TrackRole.chinese && enRole == TrackRole.foreign);
                      },
                      child: const Text('确定'),
                    ),
                  ],
                );
              },
            );
          },
        ) ??
        false;
  }

  Future<SelectedTracks?> _pickTracks(
    String videoPath,
    List<SubtitleTrackInfo> tracks,
    ExtractNeed need,
  ) async {
    if (!mounted) return null;
    final textTracks = tracks.where((t) => !t.isBitmap).toList();
    if (textTracks.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无文本字幕轨: ${p.basename(videoPath)}')),
        );
      }
      return null;
    }

    SubtitleTrackInfo? zh = TrackSelector.autoSelect(tracks).chinese;
    SubtitleTrackInfo? en = TrackSelector.autoSelect(tracks).foreign;
    var applyFolder = true;

    return showDialog<SelectedTracks>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text('选择字幕轨\n${p.basename(videoPath)}'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (need.needChinese)
                      DropdownButtonFormField<SubtitleTrackInfo>(
                        // ignore: deprecated_member_use
                        value: zh,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: '中文轨'),
                        items: textTracks
                            .map((t) => DropdownMenuItem(value: t, child: Text(t.label, overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (v) => setLocal(() => zh = v),
                      ),
                    if (need.needForeign) ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<SubtitleTrackInfo>(
                        // ignore: deprecated_member_use
                        value: en,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: '外文轨（无 eng 可选 SDH）'),
                        items: textTracks
                            .map((t) => DropdownMenuItem(value: t, child: Text(t.label, overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (v) => setLocal(() => en = v),
                      ),
                    ],
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('应用到本文件夹其余视频'),
                      value: applyFolder,
                      onChanged: (v) => setLocal(() => applyFolder = v ?? true),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('跳过')),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    ctx,
                    SelectedTracks(chinese: zh, foreign: en),
                  ),
                  child: const Text('抽取'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Color _statusColor(GroupStatus s) {
    return switch (s) {
      GroupStatus.ready || GroupStatus.done || GroupStatus.bilingualReady =>
        Colors.green.shade700,
      GroupStatus.failed || GroupStatus.conflict => Colors.red.shade700,
      GroupStatus.bilingualInline => Colors.orange.shade800,
      _ => Colors.blueGrey,
    };
  }

  Future<void> _onDrop(DropDoneDetails details) async {
    if (_busy) return;
    final paths = details.files.map((f) => f.path).where((e) => e.isNotEmpty).toList();
    if (paths.isEmpty) return;

    Directory? workDir;
    final preferFiles = <String>{};
    final modes = <String>[];

    for (final path in paths) {
      final type = FileSystemEntity.typeSync(path);
      if (type == FileSystemEntityType.directory) {
        workDir ??= Directory(path);
        modes.add('文件夹');
      } else if (type == FileSystemEntityType.file) {
        final file = File(path);
        workDir ??= Directory(p.dirname(path));
        preferFiles.add(p.normalize(file.path).toLowerCase());
        final ext = p.extension(path).toLowerCase();
        if (SubtitleLoader.exts.contains(ext)) {
          modes.add('字幕');
        } else if (_videoExts.contains(ext)) {
          modes.add('视频');
        } else {
          modes.add('文件');
        }
      }
    }

    if (workDir == null || !workDir.existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法识别拖入路径')),
        );
      }
      return;
    }

    setState(() => _dir = workDir!.path);
    await AppSettings.saveLastDir(workDir.path);
    _log.writeln('拖入: ${paths.map(p.basename).join(", ")} → 模式参考: ${modes.toSet().join("+")}');
    await _scan();

    // Prefer-select groups matching dropped files; if only dirs, keep all selected
    if (preferFiles.isNotEmpty) {
      setState(() {
        for (final g in _groups) {
          final hit = _groupTouchesFiles(g, preferFiles);
          g.selected = hit;
        }
        // if nothing matched, select all again
        if (!_groups.any((g) => g.selected)) {
          for (final g in _groups) {
            g.selected = true;
          }
        }
      });
      _log.writeln('按拖入文件勾选 ${_groups.where((g) => g.selected).length} 组');
    }

    if (_options.dragAutoRun && _groups.any((g) => g.selected)) {
      _log.writeln('拖入后自动处理（设置已开启）');
      await _run();
    }
  }

  bool _groupTouchesFiles(MatchGroup g, Set<String> preferLower) {
    bool match(File? f) =>
        f != null && preferLower.contains(p.normalize(f.path).toLowerCase());
    return match(g.chinese?.file) ||
        match(g.foreign?.file) ||
        match(g.bilingualSource) ||
        match(g.video);
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (d) async {
        setState(() => _dragging = false);
        await _onDrop(d);
      },
      child: Stack(
        children: [
          Scaffold(
      appBar: AppBar(
        title: const Text('dual-sub-merge 双语字幕合并'),
        actions: [
          IconButton(
            tooltip: '样式',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => StylesPage(
                    options: _options,
                    onChanged: (o) async {
                      _options = o;
                      await _persist();
                    },
                  ),
                ),
              );
              setState(() {});
            },
            icon: const Icon(Icons.style),
          ),
          IconButton(
            tooltip: '黑名单',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BlacklistPage(
                    options: _options,
                    onChanged: (o) async {
                      _options = o;
                      await _persist();
                    },
                  ),
                ),
              );
              setState(() {});
            },
            icon: const Icon(Icons.playlist_remove),
          ),
          IconButton(
            tooltip: '设置',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsPage(
                    options: _options,
                    onChanged: (o) async {
                      _options = o;
                      await _persist();
                    },
                  ),
                ),
              );
              setState(() {});
            },
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _dir ?? '未选择输入文件夹',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickDir,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('选择输入文件夹'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _busy || _dir == null ? null : () => _scan(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新扫描'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _outputDirLabel(),
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickOutputDir,
                  icon: const Icon(Icons.drive_folder_upload_outlined),
                  label: const Text('选择输出文件夹'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Builder(
              builder: (context) {
                final custom = _options.outputDirMode == OutputDirMode.custom;
                final chipEnabled = !_busy && !custom;
                return Wrap(
                  spacing: 4,
                  runSpacing: 0,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: _options.outputDirMode == OutputDirMode.source,
                          onChanged: chipEnabled
                              ? (v) {
                                  if (v == true) {
                                    _setOutputMode(OutputDirMode.source);
                                  }
                                }
                              : null,
                        ),
                        const Text('源文件夹'),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value:
                              _options.outputDirMode == OutputDirMode.mergedSubdir,
                          onChanged: chipEnabled
                              ? (v) {
                                  if (v == true) {
                                    _setOutputMode(OutputDirMode.mergedSubdir);
                                  }
                                }
                              : null,
                        ),
                        const Text('源文件夹/dual-sub-merged'),
                      ],
                    ),
                    if (custom)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _setOutputMode(OutputDirMode.mergedSubdir),
                        child: const Text('改回快捷目录'),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('分辨率'),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: _resIndex,
                      items: [
                        for (var i = 0; i < ResolutionPreset.list.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(ResolutionPreset.list[i].label),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _resIndex = v ?? 1),
                    ),
                  ],
                ),
                FilterChip(
                  label: const Text('删除致谢'),
                  selected: _options.removeCredits,
                  onSelected: _busy
                      ? null
                      : (v) async {
                          setState(() => _options.removeCredits = v);
                          await _persist();
                        },
                ),
                FilterChip(
                  label: const Text('从视频抽取'),
                  selected: _options.extractFromVideo,
                  onSelected: _busy
                      ? null
                      : (v) async {
                          setState(() => _options.extractFromVideo = v);
                          await _persist();
                        },
                ),
                FilterChip(
                  label: const Text('拖入后自动处理'),
                  selected: _options.dragAutoRun,
                  onSelected: _busy
                      ? null
                      : (v) async {
                          setState(() => _options.dragAutoRun = v);
                          await _persist();
                        },
                ),
                Tooltip(
                  message:
                      '开启后：无语言标记的源字幕将移动到输入目录下 chs-sub/、eng-sub/，并另存为 *.chs.* / *.eng.*',
                  child: FilterChip(
                    label: const Text('标记语言改名'),
                    selected: _options.tagLanguageOnMerge,
                    onSelected: _busy
                        ? null
                        : (v) async {
                            setState(() => _options.tagLanguageOnMerge = v);
                            final messenger = ScaffoldMessenger.of(context);
                            await _persist();
                            if (!mounted) return;
                            if (v) {
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    '已启用：无标记字幕将移入 chs-sub/eng-sub 并加上 .chs/.eng；主按钮变为「改名并合并」',
                                  ),
                                  duration: Duration(seconds: 4),
                                ),
                              );
                            }
                          },
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _renameOnly,
                  icon: const Icon(Icons.drive_file_rename_outline),
                  label: const Text('仅改名'),
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : _run,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(
                    _options.tagLanguageOnMerge ? '改名并合并' : '开始合并',
                  ),
                ),
                if (_busy) ...[
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  Text(_progress),
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (_groups.isNotEmpty)
              Row(
                children: [
                  Text(
                    '已选 ${_groups.where((g) => g.selected).length}/${_groups.length}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _busy ? null : () => _selectAll(true),
                    child: const Text('全选'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => _selectAll(false),
                    child: const Text('全不选'),
                  ),
                  TextButton(
                    onPressed: _busy || _groups.isEmpty ? null : _clearList,
                    child: const Text('清空'),
                  ),
                  const Spacer(),
                  Text(
                    '拖入文件夹/字幕/视频；\\N 双语可转换；取消勾选=不处理',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            const SizedBox(height: 4),
            Expanded(
              flex: 3,
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: _groups.isEmpty
                    ? const Center(
                        child: Text('选择或拖入输入文件夹 / 字幕 / 视频\n支持配对合并与 \\N 样式转换'),
                      )
                    : ListView.separated(
                        itemCount: _groups.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final g = _groups[i];
                          return _GroupTile(
                            group: g,
                            busy: _busy,
                            statusColor: _statusColor(g.status),
                            onSelected: (v) => setState(() => g.selected = v),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: 2,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Text('日志', style: TextStyle(fontWeight: FontWeight.bold)),
                          const Spacer(),
                          TextButton(
                            onPressed: () => setState(() => _log.clear()),
                            child: const Text('清空'),
                          ),
                        ],
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          reverse: true,
                          child: SelectableText(
                            _log.toString(),
                            style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
          ),
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.blue.withValues(alpha: 0.18),
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                    ),
                    child: const Text(
                      '释放以设为输入文件夹 / 添加字幕 / 视频',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.group,
    required this.busy,
    required this.statusColor,
    required this.onSelected,
  });

  final MatchGroup group;
  final bool busy;
  final Color statusColor;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final g = group;
    final theme = Theme.of(context);
    final zhName = g.chinese != null ? p.basename(g.chinese!.file.path) : '—';
    final enName = g.foreign != null ? p.basename(g.foreign!.file.path) : '—';

    return InkWell(
      onTap: busy ? null : () => onSelected(!g.selected),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: g.selected,
              onChanged: busy ? null : (v) => onSelected(v ?? false),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(g.kindIcon, size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        g.kindLabel,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Tooltip(
                        message: g.kindTooltip,
                        child: Icon(
                          Icons.info_outline,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          g.outputBase,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        g.status.name,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '中：$zhName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '外：$enName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  if (g.bilingualSource != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '源：${p.basename(g.bilingualSource!.path)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (g.video != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '视频：${p.basename(g.video!.path)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (g.message.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      g.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

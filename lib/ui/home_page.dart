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
  bool _dragInput = false;
  bool _dragOutput = false;
  String _progress = '';
  int _resIndex = 1; // 1080p
  /// 0 = 字幕处理, 1 = 视频处理
  int _navIndex = 0;
  static final _videoExts = {'.mkv', '.mp4'};

  List<MatchGroup> get _subtitleGroups => _groups
      .where(
        (g) =>
            g.kind == GroupKind.bilingualFile ||
            g.chinese != null ||
            g.foreign != null ||
            g.kind == GroupKind.pair,
      )
      .toList();

  List<MatchGroup> get _videoGroups =>
      _groups.where((g) => g.video != null).toList();

  List<MatchGroup> get _activeGroups =>
      _navIndex == 0 ? _subtitleGroups : _videoGroups;

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
      final groups = await FileMatcher.scanDirectory(
        Directory(_dir!),
        extractSubdir: _options.extractSubdir,
      );
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
      for (final g in _activeGroups) {
        g.selected = value;
      }
    });
  }

  void _clearList() {
    setState(() => _groups = []);
  }

  Future<void> _renameOnly() async {
    if (_dir == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先选择输入文件夹')));
      return;
    }
    final selected = _subtitleGroups.where((g) => g.selected).toList();
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

  Future<void> _extractVideos() async {
    if (_dir == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先选择输入文件夹')));
      return;
    }
    final selected =
        _videoGroups.where((g) => g.selected).map((g) => g.prefix).toSet();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请至少勾选一组视频')));
      return;
    }
    await _persist();
    setState(() {
      _busy = true;
      _progress = '抽轨中…';
    });
    final service = MergeService(
      options: _options,
      selectedPrefixes: selected,
      onProgress: (p) {
        if (!mounted) return;
        setState(() => _progress = '${p.message} (${p.current}/${p.total})');
      },
      onPickTracks: _pickTracks,
    );
    try {
      final result = await service.extractOnly(Directory(_dir!));
      _log
        ..writeln('—— 视频抽轨 ——')
        ..writeln('成功 ${result.successCount} / 失败 ${result.failCount}')
        ..writeln(result.logs.join('\n'));
      await _scan(keepSelection: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '抽轨完成：成功 ${result.successCount}，失败 ${result.failCount}',
            ),
          ),
        );
      }
    } catch (e) {
      _log.writeln('抽轨失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('抽轨失败: $e')));
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
    final selected =
        _subtitleGroups.where((g) => g.selected).map((g) => g.prefix).toSet();
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

  Future<void> _onDropInput(DropDoneDetails details) async {
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
    _log.writeln('拖入输入: ${paths.map(p.basename).join(", ")} → ${modes.toSet().join("+")}');
    await _scan();

    if (preferFiles.isNotEmpty) {
      setState(() {
        for (final g in _groups) {
          g.selected = _groupTouchesFiles(g, preferFiles);
        }
        if (!_groups.any((g) => g.selected)) {
          for (final g in _groups) {
            g.selected = true;
          }
        }
      });
      _log.writeln('按拖入文件勾选 ${_groups.where((g) => g.selected).length} 组');
    }

  }

  Future<void> _onDropOutput(DropDoneDetails details) async {
    if (_busy) return;
    final paths = details.files.map((f) => f.path).where((e) => e.isNotEmpty).toList();
    if (paths.isEmpty) return;

    String? dirPath;
    for (final path in paths) {
      final type = FileSystemEntity.typeSync(path);
      if (type == FileSystemEntityType.directory) {
        dirPath = path;
        break;
      }
    }
    if (dirPath == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请拖入文件夹作为输出目录')),
        );
      }
      return;
    }

    setState(() {
      _options.outputDirMode = OutputDirMode.custom;
      _options.customOutputDir = dirPath!;
    });
    await _persist();
    _log.writeln('拖入输出目录: $dirPath');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已设为自定义输出：$dirPath')),
      );
    }
  }

  Widget _pathDropCard({
    required String label,
    required String pathText,
    String hint = '',
    List<Widget> headerTrailing = const [],
    required bool dragging,
    required bool enabled,
    required List<Widget> trailing,
    required void Function(DropDoneDetails) onDrop,
    required void Function(bool) onDragging,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final body = Theme.of(context).textTheme.bodyMedium;
    final small = Theme.of(context).textTheme.bodySmall;
    final borderColor = dragging ? scheme.primary : scheme.outlineVariant;
    final bg = dragging
        ? scheme.primaryContainer.withValues(alpha: 0.35)
        : scheme.surfaceContainerHighest;
    final topRight = dragging
        ? Text(
            '释放以设置',
            style: small?.copyWith(color: scheme.onSurfaceVariant),
          )
        : (hint.isNotEmpty
            ? Text(
                hint,
                style: small?.copyWith(color: scheme.onSurfaceVariant),
              )
            : null);

    return DropTarget(
      enable: enabled && !_busy,
      onDragEntered: (_) => onDragging(true),
      onDragExited: (_) => onDragging(false),
      onDragDone: (d) {
        onDragging(false);
        onDrop(d);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: borderColor,
            width: dragging ? 2 : 1,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  label.contains('输入') ? Icons.input : Icons.output,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(label, style: body),
                if (headerTrailing.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  ...headerTrailing,
                ],
                const Spacer(),
                ?topRight,
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    pathText,
                    overflow: TextOverflow.ellipsis,
                    style: body,
                  ),
                ),
                const SizedBox(width: 8),
                ...trailing,
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _outputModeHeaderControls({
    required bool custom,
    required bool chipEnabled,
    required TextStyle? body,
  }) {
    return [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 28,
            width: 28,
            child: Checkbox(
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              value: _options.outputDirMode == OutputDirMode.source,
              onChanged: chipEnabled
                  ? (v) {
                      if (v == true) _setOutputMode(OutputDirMode.source);
                    }
                  : null,
            ),
          ),
          Text('源文件夹', style: body),
        ],
      ),
      const SizedBox(width: 4),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 28,
            width: 28,
            child: Checkbox(
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              value: _options.outputDirMode == OutputDirMode.mergedSubdir,
              onChanged: chipEnabled
                  ? (v) {
                      if (v == true) {
                        _setOutputMode(OutputDirMode.mergedSubdir);
                      }
                    }
                  : null,
            ),
          ),
          Text('源文件夹/dual-sub-merged', style: body),
        ],
      ),
      if (custom)
        TextButton(
          onPressed:
              _busy ? null : () => _setOutputMode(OutputDirMode.mergedSubdir),
          child: const Text('改回快捷目录'),
        ),
    ];
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
    final body = Theme.of(context).textTheme.bodyMedium;
    final custom = _options.outputDirMode == OutputDirMode.custom;
    final chipEnabled = !_busy && !custom;

    return Scaffold(
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
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _navIndex,
            onDestinationSelected: (i) => setState(() => _navIndex = i),
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.subtitles_outlined),
                selectedIcon: Icon(Icons.subtitles),
                label: Text('字幕处理'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.movie_outlined),
                selectedIcon: Icon(Icons.movie),
                label: Text('视频处理'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _navIndex == 0
                  ? _buildSubtitlePane(
                      body: body,
                      custom: custom,
                      chipEnabled: chipEnabled,
                    )
                  : _buildVideoPane(body: body),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputCard({required String hint}) {
    return _pathDropCard(
      label: '输入',
      pathText: _dir ?? '未选择输入文件夹',
      hint: hint,
      dragging: _dragInput,
      enabled: true,
      onDrop: _onDropInput,
      onDragging: (v) => setState(() => _dragInput = v),
      trailing: [
        OutlinedButton.icon(
          onPressed: _busy ? null : _pickDir,
          icon: const Icon(Icons.folder_open, size: 18),
          label: const Text('选择'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _busy || _dir == null ? null : () => _scan(),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('扫描'),
        ),
      ],
    );
  }

  Widget _buildLogCard(TextStyle? body) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('日志', style: body),
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
                  style: const TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupList({
    required List<MatchGroup> groups,
    required TextStyle? body,
    required String emptyHint,
  }) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      child: groups.isEmpty
          ? Center(
              child: Text(
                emptyHint,
                textAlign: TextAlign.center,
                style: body,
              ),
            )
          : ListView.separated(
              itemCount: groups.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              itemBuilder: (ctx, i) {
                final g = groups[i];
                return _GroupTile(
                  group: g,
                  busy: _busy,
                  statusColor: _statusColor(g.status),
                  onSelected: (v) => setState(() => g.selected = v),
                );
              },
            ),
    );
  }

  Widget _buildSubtitlePane({
    required TextStyle? body,
    required bool custom,
    required bool chipEnabled,
  }) {
    final list = _subtitleGroups;
    final selectedN = list.where((g) => g.selected).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInputCard(hint: '拖入文件夹 / 字幕 / 视频'),
        const SizedBox(height: 8),
        _pathDropCard(
          label: '输出',
          pathText: _outputDirLabel(),
          hint: '',
          headerTrailing: _outputModeHeaderControls(
            custom: custom,
            chipEnabled: chipEnabled,
            body: body,
          ),
          dragging: _dragOutput,
          enabled: true,
          onDrop: _onDropOutput,
          onDragging: (v) => setState(() => _dragOutput = v),
          trailing: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickOutputDir,
              icon: const Icon(Icons.drive_folder_upload_outlined, size: 18),
              label: const Text('选择'),
            ),
          ],
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
                Text('分辨率', style: body),
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
              Text(_progress, style: body),
            ],
          ],
        ),
        const SizedBox(height: 12),
        if (list.isNotEmpty)
          Row(
            children: [
              Text('已选 $selectedN/${list.length}', style: body),
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
                onPressed: _busy || list.isEmpty ? null : _clearList,
                child: const Text('清空'),
              ),
            ],
          ),
        const SizedBox(height: 4),
        Expanded(
          flex: 3,
          child: _buildGroupList(
            groups: list,
            body: body,
            emptyHint: '将文件夹 / 字幕拖到上方「输入」区域\n配对合并与 \\N 样式转换',
          ),
        ),
        const SizedBox(height: 8),
        Expanded(flex: 2, child: _buildLogCard(body)),
      ],
    );
  }

  Widget _buildVideoPane({required TextStyle? body}) {
    final list = _videoGroups;
    final selectedN = list.where((g) => g.selected).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInputCard(hint: '拖入文件夹 / 视频'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '从 MKV/MP4 抽取文本字幕轨到 ${_options.extractSubdir}/',
              style: body,
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _extractVideos,
              icon: const Icon(Icons.download),
              label: const Text('开始抽轨'),
            ),
            if (_busy) ...[
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              Text(_progress, style: body),
            ],
          ],
        ),
        const SizedBox(height: 12),
        if (list.isNotEmpty)
          Row(
            children: [
              Text('已选 $selectedN/${list.length}', style: body),
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
                onPressed: _busy || list.isEmpty ? null : _clearList,
                child: const Text('清空'),
              ),
            ],
          ),
        const SizedBox(height: 4),
        Expanded(
          flex: 3,
          child: _buildGroupList(
            groups: list,
            body: body,
            emptyHint: '将含字幕轨的视频拖到上方「输入」并扫描\n抽轨后可到「字幕处理」合并',
          ),
        ),
        const SizedBox(height: 8),
        Expanded(flex: 2, child: _buildLogCard(body)),
      ],
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
    final scheme = theme.colorScheme;
    final ok = g.statusOk;
    final err = !ok;
    final fg = err ? scheme.error : scheme.onSurface;
    final body = theme.textTheme.bodyMedium?.copyWith(color: fg);
    final iconColor = err ? scheme.error : scheme.primary;

    final detailLines = <String>[];
    if (g.kind == GroupKind.bilingualFile) {
      if (g.bilingualSource != null) {
        detailLines.add('源：${p.basename(g.bilingualSource!.path)}');
      }
    } else {
      final zhName =
          g.chinese != null ? p.basename(g.chinese!.file.path) : '—';
      final enName =
          g.foreign != null ? p.basename(g.foreign!.file.path) : '—';
      detailLines.add('中：$zhName');
      detailLines.add('外：$enName');
      if (g.video != null) {
        detailLines.add('视频：${p.basename(g.video!.path)}');
      }
    }

    return Material(
      color: err
          ? scheme.errorContainer.withValues(alpha: 0.45)
          : Colors.transparent,
      child: InkWell(
        onTap: busy ? null : () => onSelected(!g.selected),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: g.selected,
                onChanged: busy ? null : (v) => onSelected(v ?? false),
              ),
              Icon(g.kindIcon, size: 18, color: iconColor),
              const SizedBox(width: 6),
              Text(g.kindLabel, style: body),
              const SizedBox(width: 2),
              Tooltip(
                message: g.kindTooltip,
                child: Icon(
                  Icons.info_outline,
                  size: 16,
                  color: err ? scheme.error : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 10),
              if (ok)
                Icon(Icons.check, size: 18, color: statusColor)
              else
                Text(
                  g.statusLabelZh,
                  style: body?.copyWith(
                    color: scheme.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < detailLines.length; i++) ...[
                      if (i > 0) const SizedBox(height: 2),
                      Text(
                        detailLines[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: body,
                      ),
                    ],
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

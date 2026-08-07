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
import '../services/tools/tool_resolver.dart';
import '../services/parse/subtitle_loader.dart';
import 'blacklist_page.dart';
import 'settings_page.dart';
import 'styles_page.dart';
import 'design_system.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  MergeOptions _options = MergeOptions();
  String? _subtitleDir;
  String? _videoDir;
  Set<String> _subtitleInputFiles = {};
  Set<String> _videoInputFiles = {};
  List<MatchGroup> _groups = [];
  final _log = StringBuffer();
  final Map<String, _VideoTrackState> _videoTrackStates = {};
  bool _busy = false;
  bool _dragSubInput = false;
  bool _dragVideoInput = false;
  bool _dragOutput = false;
  String _progress = '';
  int _progressCurrent = 0;
  int _progressTotal = 0;
  double? _progressFraction;
  bool _logExpanded = false;
  int _resIndex = 1; // 1080p
  bool _showIssuesOnly = false;

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
      .where(
        (g) =>
            _subtitleInputFiles.isEmpty ||
            _groupTouchesFiles(g, _subtitleInputFiles),
      )
      .toList();

  List<MatchGroup> get _videoGroups => _groups
      .where((g) => g.video != null)
      .where(
        (g) =>
            _videoInputFiles.isEmpty || _groupTouchesFiles(g, _videoInputFiles),
      )
      .toList();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final opts = await AppSettings.loadOptions();
    setState(() {
      _options = opts;
      _resIndex = ResolutionPreset.list.indexWhere(
        (e) => e.width == opts.playResX && e.height == opts.playResY,
      );
      if (_resIndex < 0) _resIndex = 1;
    });
  }

  Future<void> _persist() => AppSettings.saveOptions(_options);

  Future<void> _pickSubtitleDir() async {
    final path = await FilePicker.getDirectoryPath(dialogTitle: '选择字幕输入文件夹');
    if (path == null) return;
    setState(() {
      _subtitleDir = path;
      _subtitleInputFiles = {};
    });
    await AppSettings.saveLastDir(path);
    await AppSettings.saveLastSubtitleFiles(const []);
    await _scan();
  }

  Future<void> _pickSubtitleFiles() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: '选择字幕文件',
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['ass', 'ssa', 'srt', 'vtt'],
    );
    final paths = result?.paths.whereType<String>().toList() ?? const [];
    if (paths.isEmpty) return;
    final dir = p.dirname(paths.first);
    setState(() {
      _subtitleDir = dir;
      _subtitleInputFiles = paths.map(_pathKey).toSet();
    });
    await AppSettings.saveLastDir(dir);
    await AppSettings.saveLastSubtitleFiles(paths);
    await _scan();
  }

  Future<void> _pickSubtitleInput() async {
    final mode = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择字幕输入'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'files'),
            child: const ListTile(
              leading: Icon(Icons.subtitles_outlined),
              title: Text('选择字幕文件'),
              subtitle: Text('支持 ASS、SSA、SRT、VTT，可多选'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'directory'),
            child: const ListTile(
              leading: Icon(Icons.folder_open_outlined),
              title: Text('选择文件夹'),
              subtitle: Text('扫描目录及字幕子目录'),
            ),
          ),
        ],
      ),
    );
    if (mode == 'files') await _pickSubtitleFiles();
    if (mode == 'directory') await _pickSubtitleDir();
  }

  Future<void> _pickVideoDir() async {
    final path = await FilePicker.getDirectoryPath(dialogTitle: '选择视频输入文件夹');
    if (path == null) return;
    setState(() {
      _videoDir = path;
      _videoInputFiles = {};
    });
    await AppSettings.saveLastVideoDir(path);
    await AppSettings.saveLastVideoFiles(const []);
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
        return _subtitleDir;
      case OutputDirMode.mergedSubdir:
        if (_subtitleDir == null) return null;
        return p.join(_subtitleDir!, MergeOptions.mergedSubdirName);
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
    final prevSelected = {for (final g in _groups) g.prefix: g.selected};
    final prevVideoSelections = {
      for (final entry in _videoTrackStates.entries)
        entry.key: Set<int>.from(entry.value.selectedIds),
    };
    setState(() {
      _busy = true;
      _progress = '扫描中…';
      _progressCurrent = 0;
      _progressTotal = 0;
      _progressFraction = null;
    });
    try {
      final filesByPath = <String, File>{};
      void addFile(File file) => filesByPath[_pathKey(file.path)] = file;

      if (_subtitleInputFiles.isNotEmpty) {
        for (final path in _subtitleInputFiles) {
          if (File(path).existsSync()) addFile(File(path));
        }
      } else if (_subtitleDir != null &&
          Directory(_subtitleDir!).existsSync()) {
        final files = await FileMatcher.listDirectoryFiles(
          Directory(_subtitleDir!),
          extractSubdir: _options.extractSubdir,
        );
        for (final file in files) {
          if (SubtitleLoader.exts.contains(
            p.extension(file.path).toLowerCase(),
          )) {
            addFile(file);
          }
        }
      }

      if (_videoInputFiles.isNotEmpty) {
        for (final path in _videoInputFiles) {
          if (File(path).existsSync()) addFile(File(path));
        }
      } else if (_videoDir != null && Directory(_videoDir!).existsSync()) {
        final files = await FileMatcher.listDirectoryFiles(
          Directory(_videoDir!),
          extractSubdir: _options.extractSubdir,
        );
        final sameAsSubtitleDir =
            _subtitleDir != null &&
            _pathKey(_subtitleDir!) == _pathKey(_videoDir!);
        for (final file in files) {
          final ext = p.extension(file.path).toLowerCase();
          if (_videoExts.contains(ext) ||
              (!sameAsSubtitleDir && SubtitleLoader.exts.contains(ext))) {
            addFile(file);
          }
        }
      }

      final all = await FileMatcher.scanFiles(
        filesByPath.values,
        extractSubdir: _options.extractSubdir,
      );
      for (final g in all) {
        // default: all selected; preserve prior choice on refresh
        if (keepSelection && prevSelected.containsKey(g.prefix)) {
          g.selected = prevSelected[g.prefix]!;
        } else {
          g.selected = true;
        }
      }
      setState(() {
        _groups = all;
        final n = _groups.where((e) => e.selected).length;
        _log.writeln(
          '扫描 ${_groups.length} 组（默认全选 $n）'
          '@ 字幕=${_subtitleDir ?? "-"} 视频=${_videoDir ?? "-"}',
        );
      });
      await _loadVideoTracks(
        all,
        previousSelections: keepSelection ? prevVideoSelections : const {},
      );
    } catch (e) {
      _log.writeln('扫描失败: $e');
    } finally {
      setState(() {
        _busy = false;
        _progress = '';
        _progressCurrent = 0;
        _progressTotal = 0;
        _progressFraction = null;
      });
    }
  }

  Future<void> _loadVideoTracks(
    List<MatchGroup> groups, {
    required Map<String, Set<int>> previousSelections,
  }) async {
    final videos = groups.where((group) => group.video != null).toList();
    final paths = videos.map((group) => group.video!.path).toSet();
    _videoTrackStates.removeWhere((path, _) => !paths.contains(path));
    if (videos.isEmpty) return;

    setState(() {
      for (final group in videos) {
        _videoTrackStates[group.video!.path] = _VideoTrackState.loading();
      }
    });

    final tools = await ToolResolver.resolve(
      mkvToolNixDir: _options.mkvToolNixDir,
      ffmpegPath: _options.ffmpegPath,
      ffprobePath: _options.ffprobePath,
    );
    final extractor = ExtractService(tools, _options);

    for (var i = 0; i < videos.length; i++) {
      final group = videos[i];
      final video = group.video!;
      if (mounted) {
        setState(() {
          _progress = '读取字幕轨：${group.outputBase} (${i + 1}/${videos.length})';
          _progressCurrent = i + 1;
          _progressTotal = videos.length;
        });
      }
      try {
        final tracks = await extractor.probeTracks(video);
        final previous = previousSelections[video.path];
        final automatic = TrackSelector.autoSelect(tracks);
        final selectedIds = previous == null
            ? {
                for (final track in [automatic.chinese, automatic.foreign])
                  if (track != null && !track.isBitmap) track.id,
              }
            : previous
                  .where(
                    (id) => tracks.any(
                      (track) => track.id == id && !track.isBitmap,
                    ),
                  )
                  .toSet();
        if (!mounted) return;
        setState(() {
          _videoTrackStates[video.path] = _VideoTrackState.ready(
            tracks: tracks,
            selectedIds: selectedIds,
          );
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _videoTrackStates[video.path] = _VideoTrackState.failed('$e');
        });
      }
    }
  }

  bool _isVideoGroupSelected(MatchGroup group) {
    final path = group.video?.path;
    return path != null &&
        (_videoTrackStates[path]?.selectedIds.isNotEmpty ?? false);
  }

  void _setVideoGroupSelected(MatchGroup group, bool selected) {
    final path = group.video?.path;
    final state = path == null ? null : _videoTrackStates[path];
    if (state == null || state.loading) return;
    setState(() {
      state.selectedIds
        ..clear()
        ..addAll(
          selected
              ? state.tracks
                    .where((track) => !track.isBitmap)
                    .map((track) => track.id)
              : const <int>[],
        );
    });
  }

  void _setVideoTrackSelected(
    MatchGroup group,
    SubtitleTrackInfo track,
    bool selected,
  ) {
    final path = group.video?.path;
    final state = path == null ? null : _videoTrackStates[path];
    if (state == null || state.loading || track.isBitmap) return;
    setState(() {
      if (selected) {
        state.selectedIds.add(track.id);
      } else {
        state.selectedIds.remove(track.id);
      }
    });
  }

  bool _groupNeedsCheck(MatchGroup group, {required bool videoMode}) {
    if (videoMode) {
      final path = group.video?.path;
      return path != null && _videoTrackStates[path]?.error != null;
    }
    return !group.statusOk;
  }

  List<MatchGroup> _visibleGroups(
    List<MatchGroup> groups, {
    required bool videoMode,
  }) {
    if (!_showIssuesOnly) return groups;
    final issues = groups
        .where((g) => _groupNeedsCheck(g, videoMode: videoMode))
        .toList();
    return issues.isEmpty ? groups : issues;
  }

  void _selectAll(bool value) {
    setState(() {
      if (_navIndex == 1) {
        final targets = _visibleGroups(_videoGroups, videoMode: true);
        for (final g in targets) {
          final path = g.video?.path;
          final state = path == null ? null : _videoTrackStates[path];
          if (state == null) continue;
          state.selectedIds
            ..clear()
            ..addAll(
              value
                  ? state.tracks
                        .where((track) => !track.isBitmap)
                        .map((track) => track.id)
                  : const <int>[],
            );
        }
        return;
      }
      for (final g in _visibleGroups(_subtitleGroups, videoMode: false)) {
        g.selected = value;
      }
    });
  }

  void _clearList() {
    setState(() {
      _groups = [];
      _videoTrackStates.clear();
      _showIssuesOnly = false;
    });
  }

  Future<void> _renameOnly() async {
    if (_subtitleDir == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先选择字幕输入文件夹')));
      return;
    }
    final selected = _subtitleGroups.where((g) => g.selected).toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少勾选一组字幕')));
      return;
    }
    setState(() {
      _busy = true;
      _progress = '标记语言改名…';
      _progressCurrent = 0;
      _progressTotal = 0;
    });
    try {
      final r = await LanguageTagRenameService().renameGroups(
        inputDir: Directory(_subtitleDir!),
        groups: selected,
        overwrite: _options.overwrite,
      );
      _log
        ..writeln('—— 仅改名 ——')
        ..writeln(r.logs.join('\n'))
        ..writeln(
          '完成 ${r.renamedCount}，跳过 ${r.skippedCount}，失败 ${r.failCount}',
        );
      await _syncExplicitSubtitleFiles(selected);
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('改名失败: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = '';
          _progressCurrent = 0;
          _progressTotal = 0;
        });
      }
    }
  }

  Future<void> _extractVideos() async {
    if (_videoDir == null && _videoInputFiles.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先选择或拖入视频')));
      return;
    }
    final sourceGroups = _videoGroups;
    final selectedTrackIdsByVideo = <String, Set<int>>{
      for (final group in sourceGroups)
        if (group.video != null && _isVideoGroupSelected(group))
          group.video!.path: Set<int>.from(
            _videoTrackStates[group.video!.path]!.selectedIds,
          ),
    };
    final selected = sourceGroups
        .where(
          (group) =>
              group.video != null &&
              selectedTrackIdsByVideo.containsKey(group.video!.path),
        )
        .map((group) => group.prefix)
        .toSet();
    if (selectedTrackIdsByVideo.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少勾选一条需要抽取的字幕轨')));
      return;
    }
    await _persist();
    setState(() {
      _busy = true;
      _progress = '抽轨中…';
      _progressCurrent = 0;
      _progressTotal = selectedTrackIdsByVideo.length;
      _progressFraction = 0;
    });
    final service = MergeService(
      options: _options,
      selectedPrefixes: selected,
      onProgress: (p) {
        if (!mounted) return;
        setState(() {
          _progress = p.message;
          _progressCurrent = p.current;
          _progressTotal = p.total;
          _progressFraction = p.fraction;
        });
      },
      onPickTracks: _pickTracks,
      selectedTrackIdsByVideo: selectedTrackIdsByVideo,
    );
    try {
      final result = await service.extractOnly(
        Directory(_videoDir ?? p.dirname(sourceGroups.first.video!.path)),
        sourceGroups: sourceGroups,
      );
      _log
        ..writeln('—— 视频抽轨 ——')
        ..writeln('成功 ${result.successCount} / 失败 ${result.failCount}')
        ..writeln(result.logs.join('\n'));
      if (result.failCount == 0) {
        for (final path in selectedTrackIdsByVideo.keys) {
          _videoTrackStates[path]?.selectedIds.clear();
        }
      }
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('抽轨失败: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = '';
          _progressCurrent = 0;
          _progressTotal = 0;
          _progressFraction = null;
        });
      }
    }
  }

  Future<void> _run() async {
    if (_subtitleDir == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先选择字幕输入文件夹')));
      return;
    }
    final outPath = _resolvedOutputDir();
    if (outPath == null || outPath.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先选择输出文件夹')));
      return;
    }
    final sourceGroups = _subtitleGroups;
    final selected = sourceGroups
        .where((g) => g.selected)
        .map((g) => g.prefix)
        .toSet();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少勾选一组字幕')));
      return;
    }
    final res = ResolutionPreset
        .list[_resIndex.clamp(0, ResolutionPreset.list.length - 1)];
    _options.playResX = res.width;
    _options.playResY = res.height;
    await _persist();

    setState(() {
      _busy = true;
      _progress = '处理中…';
      _progressCurrent = 0;
      _progressTotal = 0;
    });

    final service = MergeService(
      options: _options,
      selectedPrefixes: selected,
      onProgress: (p) {
        if (!mounted) return;
        setState(() {
          _progress = p.message;
          _progressCurrent = p.current;
          _progressTotal = p.total;
        });
      },
      onConflict: _resolveConflict,
    );

    try {
      final result = await service.run(
        Directory(_subtitleDir!),
        outputDir: Directory(outPath),
        sourceGroups: sourceGroups,
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
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('知道了'),
                ),
              ],
            ),
          );
        }
      }
      if (_options.tagLanguageOnMerge) {
        await _syncExplicitSubtitleFiles(sourceGroups);
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('失败: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = '';
          _progressCurrent = 0;
          _progressTotal = 0;
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
                  title: const Text('解决字幕角色冲突'),
                  content: SizedBox(
                    width: 500,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              ctx,
                            ).colorScheme.errorContainer.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 19,
                                color: Theme.of(ctx).colorScheme.error,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      group.outputBase,
                                      style: Theme.of(ctx).textTheme.titleSmall,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      group.message.isEmpty
                                          ? '请为两个文件指定正确的字幕角色。'
                                          : group.message,
                                      style: Theme.of(ctx).textTheme.bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              ctx,
                                            ).colorScheme.onErrorContainer,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<File>(
                          // ignore: deprecated_member_use
                          value: zhFile,
                          decoration: const InputDecoration(
                            labelText: '中文字幕',
                            prefixIcon: Icon(Icons.translate_rounded),
                          ),
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
                          decoration: const InputDecoration(
                            labelText: '外文字幕',
                            prefixIcon: Icon(Icons.language_rounded),
                          ),
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
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('跳过此项'),
                    ),
                    FilledButton(
                      onPressed: () {
                        if (zhFile != null) {
                          group.chinese = SubtitleFileRef(
                            file: zhFile!,
                            role: TrackRole.chinese,
                          );
                          zhRole = TrackRole.chinese;
                        }
                        if (enFile != null) {
                          group.foreign = SubtitleFileRef(
                            file: enFile!,
                            role: TrackRole.foreign,
                          );
                          enRole = TrackRole.foreign;
                        }
                        Navigator.pop(
                          ctx,
                          zhRole == TrackRole.chinese &&
                              enRole == TrackRole.foreign,
                        );
                      },
                      child: const Text('应用选择'),
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
              title: const Text('选择文本字幕轨'),
              content: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                            Icons.video_file_outlined,
                            size: 19,
                            color: UiTokens.muted,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(p.basename(videoPath), softWrap: true),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (need.needChinese)
                      DropdownButtonFormField<SubtitleTrackInfo>(
                        // ignore: deprecated_member_use
                        value: zh,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '中文轨',
                          prefixIcon: Icon(Icons.translate_rounded),
                        ),
                        items: textTracks
                            .map(
                              (t) => DropdownMenuItem(
                                value: t,
                                child: Text(
                                  t.label,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setLocal(() => zh = v),
                      ),
                    if (need.needForeign) ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<SubtitleTrackInfo>(
                        // ignore: deprecated_member_use
                        value: en,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '外文轨（无 eng 时可选 SDH）',
                          prefixIcon: Icon(Icons.language_rounded),
                        ),
                        items: textTracks
                            .map(
                              (t) => DropdownMenuItem(
                                value: t,
                                child: Text(
                                  t.label,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
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
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('跳过'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    ctx,
                    SelectedTracks(chinese: zh, foreign: en),
                  ),
                  child: const Text('确认并抽取'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _onDropInput(
    DropDoneDetails details, {
    required bool video,
  }) async {
    if (_busy) return;
    final paths = details.files
        .map((f) => f.path)
        .where((e) => e.isNotEmpty)
        .toList();
    if (paths.isEmpty) return;

    Directory? workDir;
    var containsDirectory = false;
    final preferFiles = <String>{};
    final modes = <String>[];

    for (final path in paths) {
      final type = FileSystemEntity.typeSync(path);
      if (type == FileSystemEntityType.directory) {
        workDir ??= Directory(path);
        containsDirectory = true;
        modes.add('文件夹');
      } else if (type == FileSystemEntityType.file) {
        final file = File(path);
        final ext = p.extension(path).toLowerCase();
        final accepted = video
            ? _videoExts.contains(ext)
            : SubtitleLoader.exts.contains(ext);
        if (!accepted) {
          modes.add('不支持的文件');
          continue;
        }
        workDir ??= Directory(p.dirname(path));
        preferFiles.add(_pathKey(file.path));
        if (!video) {
          modes.add('字幕');
        } else {
          modes.add('视频');
        }
      }
    }

    if (workDir == null || !workDir.existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法识别拖入路径')));
      }
      return;
    }

    setState(() {
      if (video) {
        _videoDir = workDir!.path;
        _videoInputFiles = containsDirectory ? {} : preferFiles;
      } else {
        _subtitleDir = workDir!.path;
        _subtitleInputFiles = containsDirectory
            ? {}
            : preferFiles
                  .where(
                    (path) => SubtitleLoader.exts.contains(p.extension(path)),
                  )
                  .toSet();
      }
    });
    if (video) {
      await AppSettings.saveLastVideoDir(workDir.path);
      await AppSettings.saveLastVideoFiles(_videoInputFiles);
    } else {
      await AppSettings.saveLastDir(workDir.path);
      await AppSettings.saveLastSubtitleFiles(_subtitleInputFiles);
    }
    _log.writeln(
      '拖入${video ? "视频" : "字幕"}输入: ${paths.map(p.basename).join(", ")} → ${modes.toSet().join("+")}',
    );
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
    final paths = details.files
        .map((f) => f.path)
        .where((e) => e.isNotEmpty)
        .toList();
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请拖入文件夹作为输出目录')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已设为自定义输出：$dirPath')));
    }
  }

  Widget _pathDropCard({
    required String label,
    required String pathText,
    required String hint,
    required bool dragging,
    required bool enabled,
    required IconData icon,
    required List<Widget> trailing,
    required void Function(DropDoneDetails) onDrop,
    required void Function(bool) onDragging,
    Widget? controls,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final hasPath = !pathText.startsWith('未选择');
    final displayPath = pathText.replaceAllMapped(
      RegExp(r'[\\/]'),
      (match) => '${match.group(0)}\u200B',
    );
    return DropTarget(
      enable: enabled && !_busy,
      onDragEntered: (_) => onDragging(true),
      onDragExited: (_) => onDragging(false),
      onDragDone: (d) {
        onDragging(false);
        onDrop(d);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: dragging
              ? scheme.primaryContainer.withValues(alpha: 0.65)
              : UiTokens.subtle,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: dragging ? scheme.primary : UiTokens.border,
            width: dragging ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: dragging
                    ? scheme.primary.withValues(alpha: 0.12)
                    : scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 18,
                color: dragging ? scheme.primary : UiTokens.muted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          dragging ? '释放以设置并扫描' : hint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Tooltip(
                    message: hasPath ? pathText : '',
                    child: Text(
                      displayPath,
                      softWrap: true,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: hasPath ? scheme.onSurface : UiTokens.muted,
                        height: 1.35,
                      ),
                    ),
                  ),
                  if (controls != null) ...[
                    const SizedBox(height: 9),
                    controls,
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            ...trailing,
          ],
        ),
      ),
    );
  }

  bool _groupTouchesFiles(MatchGroup g, Set<String> preferLower) {
    bool match(File? f) => f != null && preferLower.contains(_pathKey(f.path));
    return match(g.chinese?.file) ||
        match(g.foreign?.file) ||
        match(g.bilingualSource) ||
        match(g.video);
  }

  String _pathKey(String path) => p.normalize(p.absolute(path)).toLowerCase();

  Future<void> _syncExplicitSubtitleFiles(Iterable<MatchGroup> groups) async {
    if (_subtitleInputFiles.isEmpty) return;
    final paths = <String>{};
    for (final group in groups) {
      for (final file in [
        group.chinese?.file,
        group.foreign?.file,
        group.bilingualSource,
      ]) {
        if (file != null && file.existsSync()) paths.add(_pathKey(file.path));
      }
    }
    setState(() => _subtitleInputFiles = paths);
    await AppSettings.saveLastSubtitleFiles(paths);
  }

  Future<void> _openStyles() async {
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
    if (mounted) setState(() {});
  }

  Future<void> _openBlacklist() async {
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
    if (mounted) setState(() {});
  }

  Future<void> _openSettings() async {
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
    if (mounted) setState(() {});
  }

  Widget _buildSidebar({required bool compact}) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: compact ? UiTokens.sidebarCompactWidth : UiTokens.sidebarWidth,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: const Border(right: BorderSide(color: UiTokens.border)),
      ),
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 12,
        16,
        compact ? 10 : 12,
        12,
      ),
      child: Column(
        crossAxisAlignment: compact
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 0 : 6,
              vertical: 4,
            ),
            child: Row(
              mainAxisAlignment: compact
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.subtitles_rounded,
                    color: Colors.white,
                    size: 19,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'dual-sub-merge',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '字幕工作台',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 22),
          if (!compact)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: Text(
                '工作区',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: UiTokens.muted,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          SidebarNavItem(
            icon: Icons.subtitles_outlined,
            label: '字幕处理',
            selected: _navIndex == 0,
            compact: compact,
            onTap: () {
              if (_navIndex != 0) setState(() => _navIndex = 0);
            },
          ),
          const SizedBox(height: 2),
          SidebarNavItem(
            icon: Icons.movie_outlined,
            label: '视频处理',
            selected: _navIndex == 1,
            compact: compact,
            onTap: () {
              if (_navIndex != 1) setState(() => _navIndex = 1);
            },
          ),
          const Spacer(),
          if (!compact)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: Text(
                '配置',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: UiTokens.muted,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          SidebarNavItem(
            icon: Icons.style_outlined,
            label: '字幕样式',
            selected: false,
            compact: compact,
            onTap: _openStyles,
          ),
          const SizedBox(height: 2),
          SidebarNavItem(
            icon: Icons.playlist_remove_outlined,
            label: '致谢黑名单',
            selected: false,
            compact: compact,
            onTap: _openBlacklist,
          ),
          const SizedBox(height: 2),
          SidebarNavItem(
            icon: Icons.settings_outlined,
            label: '设置',
            selected: false,
            compact: compact,
            onTap: _openSettings,
          ),
          if (!compact) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'v0.3.0',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: UiTokens.muted.withValues(alpha: 0.75),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compactSidebar = constraints.maxWidth < 1080;
          final compactPage = constraints.maxWidth < 1180;
          return Row(
            children: [
              _buildSidebar(compact: compactSidebar),
              const VerticalDivider(width: 1),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: UiTokens.pageMaxWidth,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(
                        compactPage
                            ? UiTokens.pagePaddingCompact
                            : UiTokens.pagePadding,
                      ),
                      child: _navIndex == 0
                          ? _buildSubtitlePane(compact: compactPage)
                          : _buildVideoPane(compact: compactPage),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInputCard({
    required String hint,
    required String? dir,
    required bool video,
  }) {
    final pathText = video && _videoInputFiles.isNotEmpty
        ? '已选择 ${_videoInputFiles.length} 个视频文件 · ${dir ?? ""}'
        : !video && _subtitleInputFiles.isNotEmpty
        ? '已选择 ${_subtitleInputFiles.length} 个字幕文件 · ${dir ?? ""}'
        : dir ?? (video ? '未选择视频文件夹' : '未选择字幕文件夹');
    return _pathDropCard(
      label: video ? '视频来源' : '输入来源',
      pathText: pathText,
      hint: hint,
      icon: video ? Icons.movie_filter_outlined : Icons.input_rounded,
      dragging: video ? _dragVideoInput : _dragSubInput,
      enabled: true,
      onDrop: (d) => _onDropInput(d, video: video),
      onDragging: (v) => setState(() {
        if (video) {
          _dragVideoInput = v;
        } else {
          _dragSubInput = v;
        }
      }),
      trailing: [
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : (video ? _pickVideoDir : _pickSubtitleInput),
          icon: const Icon(Icons.folder_open_outlined, size: 17),
          label: const Text('选择'),
        ),
        const SizedBox(width: 8),
        FilledButton.tonalIcon(
          onPressed: _busy || dir == null ? null : () => _scan(),
          icon: const Icon(Icons.refresh_rounded, size: 17),
          label: const Text('扫描'),
        ),
      ],
    );
  }

  Widget _buildOutputCard() {
    final modeLabel = switch (_options.outputDirMode) {
      OutputDirMode.mergedSubdir => '合并目录',
      OutputDirMode.source => '源文件夹',
      OutputDirMode.custom => '自定义',
    };
    return _pathDropCard(
      label: '输出位置',
      pathText: _outputDirLabel(),
      hint: '拖入目录可直接设为自定义输出',
      icon: Icons.output_rounded,
      dragging: _dragOutput,
      enabled: true,
      onDrop: _onDropOutput,
      onDragging: (v) => setState(() => _dragOutput = v),
      trailing: [
        PopupMenuButton<OutputDirMode>(
          tooltip: '选择输出模式',
          enabled: !_busy,
          onSelected: (mode) async {
            if (mode == OutputDirMode.custom) {
              await _pickOutputDir();
            } else {
              _setOutputMode(mode);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: OutputDirMode.mergedSubdir,
              child: ListTile(
                dense: true,
                leading: Icon(Icons.create_new_folder_outlined),
                title: Text('输入/dual-sub-merged'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: OutputDirMode.source,
              child: ListTile(
                dense: true,
                leading: Icon(Icons.folder_outlined),
                title: Text('源文件夹'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: OutputDirMode.custom,
              child: ListTile(
                dense: true,
                leading: Icon(Icons.tune_rounded),
                title: Text('选择自定义目录'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
          child: IgnorePointer(
            child: OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.folder_copy_outlined, size: 17),
              label: Text(modeLabel),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogPanel() {
    final hasLog = _log.isNotEmpty;
    final showBar = _busy && _progressTotal > 0;
    final progressText = !_busy
        ? '运行详情'
        : showBar
        ? _progressFraction != null
              ? '$_progress（视频 $_progressCurrent/$_progressTotal）'
              : '$_progress ($_progressCurrent/$_progressTotal)'
        : _progress;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: _logExpanded ? 176 : (showBar ? 72 : 42),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: UiTokens.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _logExpanded = !_logExpanded),
            child: SizedBox(
              height: showBar ? 66 : 40,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(
                      _busy ? Icons.sync_rounded : Icons.terminal_rounded,
                      size: 17,
                      color: _busy
                          ? Theme.of(context).colorScheme.primary
                          : UiTokens.muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        progressText,
                        softWrap: true,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    if (!_busy && hasLog) ...[
                      const SizedBox(width: 8),
                      const StatusBadge(
                        label: '有记录',
                        foreground: UiTokens.muted,
                        background: Color(0xFFF0F3F7),
                      ),
                    ],
                    const Spacer(),
                    if (_logExpanded && hasLog)
                      TextButton(
                        onPressed: () => setState(() => _log.clear()),
                        child: const Text('清空'),
                      ),
                    Icon(
                      _logExpanded ? Icons.expand_more : Icons.chevron_right,
                      size: 18,
                      color: UiTokens.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (showBar)
            LinearProgressIndicator(
              value: _progressTotal > 0
                  ? _progressFraction ??
                        (_progressCurrent / _progressTotal).clamp(0.0, 1.0)
                  : null,
              minHeight: 3,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
              color: Theme.of(context).colorScheme.primary,
            ),
          if (_logExpanded) ...[
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                reverse: true,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: SelectableText(
                  hasLog ? _log.toString() : '尚无运行记录。扫描、合并或抽轨后，详细信息会显示在这里。',
                  style: TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 12,
                    height: 1.45,
                    color: hasLog ? null : UiTokens.muted,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGroupList({
    required List<MatchGroup> groups,
    required String emptyTitle,
    required String emptyHint,
    required IconData emptyIcon,
    bool showVideoTracks = false,
  }) {
    final selectedN = showVideoTracks
        ? groups.where(_isVideoGroupSelected).length
        : groups.where((group) => group.selected).length;
    final issueN = groups
        .where((g) => _groupNeedsCheck(g, videoMode: showVideoTracks))
        .length;
    final filtering = _showIssuesOnly && issueN > 0;
    final visible = filtering
        ? groups
              .where((g) => _groupNeedsCheck(g, videoMode: showVideoTracks))
              .toList()
        : groups;
    return AppSurface(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 10, 12),
            child: Row(
              children: [
                Text('任务列表', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 10),
                StatusBadge(
                  label: '${groups.length} 项',
                  foreground: UiTokens.muted,
                  background: const Color(0xFFF0F3F7),
                ),
                if (groups.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  StatusBadge(
                    label: '已选 $selectedN',
                    foreground: Theme.of(context).colorScheme.primary,
                    background: Theme.of(context).colorScheme.primaryContainer,
                  ),
                  if (issueN > 0) ...[
                    const SizedBox(width: 6),
                    Tooltip(
                      message: filtering ? '显示全部' : '仅显示需检查项',
                      child: FilterChip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        selected: filtering,
                        showCheckmark: false,
                        avatar: const Icon(
                          Icons.priority_high_rounded,
                          size: 14,
                          color: UiTokens.warning,
                        ),
                        label: Text('$issueN 项需检查'),
                        labelStyle: const TextStyle(
                          color: UiTokens.warning,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        selectedColor: UiTokens.warningBg,
                        backgroundColor: UiTokens.warningBg,
                        side: BorderSide(
                          color: filtering ? UiTokens.warning : UiTokens.border,
                        ),
                        onSelected: _busy
                            ? null
                            : (v) => setState(() => _showIssuesOnly = v),
                      ),
                    ),
                  ],
                ],
                const Spacer(),
                if (groups.isNotEmpty) ...[
                  TextButton(
                    onPressed: _busy ? null : () => _selectAll(true),
                    child: const Text('全选'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => _selectAll(false),
                    child: const Text('取消选择'),
                  ),
                  IconButton(
                    tooltip: '清空列表',
                    onPressed: _busy ? null : _clearList,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 19),
                  ),
                ],
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: groups.isEmpty
                ? _buildEmptyGroupState(
                    title: emptyTitle,
                    hint: emptyHint,
                    icon: emptyIcon,
                  )
                : visible.isEmpty
                ? _buildEmptyGroupState(
                    title: '没有需检查的项',
                    hint: '关闭「仅显示需检查」可查看全部任务。',
                    icon: Icons.fact_check_outlined,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) =>
                        const Divider(indent: 16, endIndent: 16),
                    itemBuilder: (context, index) {
                      final g = visible[index];
                      final videoState = showVideoTracks && g.video != null
                          ? _videoTrackStates[g.video!.path] ??
                                _VideoTrackState.loading()
                          : null;
                      return _GroupTile(
                        group: g,
                        selected: showVideoTracks
                            ? _isVideoGroupSelected(g)
                            : g.selected,
                        busy: _busy,
                        videoTracks: videoState,
                        onSelected: (value) {
                          if (showVideoTracks) {
                            _setVideoGroupSelected(g, value);
                          } else {
                            setState(() => g.selected = value);
                          }
                        },
                        onTrackSelected: (track, value) =>
                            _setVideoTrackSelected(g, track, value),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyGroupState({
    required String title,
    required String hint,
    required IconData icon,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final condensed = constraints.maxHeight < 160;
        final iconBox = Container(
          width: condensed ? 34 : 46,
          height: condensed ? 34 : 46,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(condensed ? 10 : 14),
          ),
          child: Icon(icon, color: UiTokens.muted, size: condensed ? 19 : 25),
        );
        if (condensed) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  iconBox,
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hint.replaceAll('\n', ' '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                iconBox,
                const SizedBox(height: 14),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _setResolutionIndex(int i) async {
    final res =
        ResolutionPreset.list[i.clamp(0, ResolutionPreset.list.length - 1)];
    setState(() {
      _resIndex = i;
      _options.playResX = res.width;
      _options.playResY = res.height;
    });
    await _persist();
  }

  Widget _buildSubtitleActions({required bool compact}) {
    return AppSurface(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ResolutionPicker(
            index: _resIndex,
            enabled: !_busy,
            onChanged: (i) {
              _setResolutionIndex(i);
            },
          ),
          FilterChip(
            avatar: Icon(
              Icons.auto_delete_outlined,
              size: 16,
              color: _options.removeCredits
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            label: const Text('删除致谢'),
            selected: _options.removeCredits,
            showCheckmark: false,
            onSelected: _busy
                ? null
                : (v) async {
                    setState(() => _options.removeCredits = v);
                    await _persist();
                  },
          ),
          Tooltip(
            message: '无语言标记的源字幕将移入 chs-sub / eng-sub，并补上 .chs / .eng',
            child: FilterChip(
              avatar: Icon(
                Icons.drive_file_rename_outline,
                size: 16,
                color: _options.tagLanguageOnMerge
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              label: const Text('标记语言改名'),
              selected: _options.tagLanguageOnMerge,
              showCheckmark: false,
              onSelected: _busy
                  ? null
                  : (v) async {
                      setState(() => _options.tagLanguageOnMerge = v);
                      await _persist();
                    },
            ),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _renameOnly,
            icon: const Icon(Icons.drive_file_rename_outline, size: 17),
            label: const Text('仅改名'),
          ),
          FilledButton.icon(
            onPressed: _busy ? null : _run,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.play_arrow_rounded, size: 19),
            label: Text(
              _busy ? '处理中' : (_options.tagLanguageOnMerge ? '改名并合并' : '开始合并'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubtitlePane({required bool compact}) {
    final list = _subtitleGroups;
    final gap = compact ? 8.0 : 12.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(
          title: '字幕处理',
          description: '配对中外单语字幕，或将上下双语字幕转换为规范的 .chs+eng.ass。',
        ),
        SizedBox(height: compact ? 10 : 16),
        AppSurface(
          padding: EdgeInsets.all(compact ? 8 : 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 1250) {
                return Column(
                  children: [
                    _buildInputCard(
                      hint: '支持目录、ASS、SRT、VTT 与视频文件',
                      dir: _subtitleDir,
                      video: false,
                    ),
                    const SizedBox(height: 10),
                    _buildOutputCard(),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildInputCard(
                      hint: '目录、字幕或视频',
                      dir: _subtitleDir,
                      video: false,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _buildOutputCard()),
                ],
              );
            },
          ),
        ),
        SizedBox(height: gap),
        _buildSubtitleActions(compact: compact),
        SizedBox(height: gap),
        Expanded(
          child: _buildGroupList(
            groups: list,
            emptyTitle: '尚未发现可处理的字幕',
            emptyHint: '选择或拖入输入目录，然后点击“扫描”。\n可处理单语配对与含 \\N 的上下双语字幕。',
            emptyIcon: Icons.subtitles_off_outlined,
          ),
        ),
        SizedBox(height: gap),
        _buildLogPanel(),
      ],
    );
  }

  Widget _buildVideoPane({required bool compact}) {
    final list = _videoGroups;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: '视频处理',
          description:
              '从 MKV / MP4 中识别并抽取文本字幕轨，输出到 ${_options.extractSubdir}/。',
        ),
        const SizedBox(height: 16),
        AppSurface(
          padding: const EdgeInsets.all(12),
          child: _buildInputCard(
            hint: '支持拖入单个或多个 MKV / MP4，也可拖入目录',
            dir: _videoDir,
            video: true,
          ),
        ),
        const SizedBox(height: 12),
        AppSurface(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.download_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '抽取字幕轨',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '展开查看容器内全部字幕轨，勾选后抽取；PGS / VobSub 仅展示，不可勾选。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : _extractVideos,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.download_rounded, size: 18),
                label: Text(_busy ? '抽取中' : '开始抽轨'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _buildGroupList(
            groups: list,
            emptyTitle: '尚未发现可处理的视频',
            emptyHint: '将含字幕轨的视频或目录拖到输入区域并扫描。\n抽轨完成后可返回“字幕处理”继续合并。',
            emptyIcon: Icons.video_file_outlined,
            showVideoTracks: true,
          ),
        ),
        const SizedBox(height: 10),
        _buildLogPanel(),
      ],
    );
  }
}

class _VideoTrackState {
  _VideoTrackState({
    required this.loading,
    required this.tracks,
    required this.selectedIds,
    this.error,
  });

  factory _VideoTrackState.loading() =>
      _VideoTrackState(loading: true, tracks: const [], selectedIds: <int>{});

  factory _VideoTrackState.ready({
    required List<SubtitleTrackInfo> tracks,
    required Set<int> selectedIds,
  }) => _VideoTrackState(
    loading: false,
    tracks: tracks,
    selectedIds: selectedIds,
  );

  factory _VideoTrackState.failed(String error) => _VideoTrackState(
    loading: false,
    tracks: const [],
    selectedIds: <int>{},
    error: error,
  );

  final bool loading;
  final List<SubtitleTrackInfo> tracks;
  final Set<int> selectedIds;
  final String? error;
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.group,
    required this.selected,
    required this.busy,
    required this.onSelected,
    required this.onTrackSelected,
    this.videoTracks,
  });

  final MatchGroup group;
  final bool selected;
  final bool busy;
  final ValueChanged<bool> onSelected;
  final void Function(SubtitleTrackInfo track, bool selected) onTrackSelected;
  final _VideoTrackState? videoTracks;

  @override
  Widget build(BuildContext context) {
    final g = group;
    final scheme = Theme.of(context).colorScheme;
    final isVideoMode = videoTracks != null;
    final detailLines = <(String, String)>[];
    if (isVideoMode) {
      detailLines.add((
        '视频',
        g.video == null ? '—' : p.basename(g.video!.path),
      ));
    } else if (g.kind == GroupKind.bilingualFile) {
      detailLines.add((
        '源',
        g.bilingualSource == null ? '—' : p.basename(g.bilingualSource!.path),
      ));
    } else {
      detailLines.add((
        '中',
        g.chinese == null ? '—' : p.basename(g.chinese!.file.path),
      ));
      detailLines.add((
        '外',
        g.foreign == null ? '—' : p.basename(g.foreign!.file.path),
      ));
      if (g.video != null) detailLines.add(('视频', p.basename(g.video!.path)));
    }

    final status = isVideoMode
        ? _videoStatus(context)
        : g.statusOk
        ? const StatusBadge(
            label: '就绪',
            icon: Icons.check_rounded,
            foreground: UiTokens.success,
            background: UiTokens.successBg,
          )
        : StatusBadge(
            label: g.statusLabelZh,
            icon: Icons.priority_high_rounded,
            foreground: UiTokens.warning,
            background: UiTokens.warningBg,
          );

    final selectableTracks = videoTracks?.tracks
        .where((track) => !track.isBitmap)
        .length;
    final selectedTrackCount = videoTracks?.selectedIds.length ?? 0;
    final bool? groupCheckboxValue = !isVideoMode
        ? selected
        : selectedTrackCount == 0
        ? false
        : selectedTrackCount == selectableTracks
        ? true
        : null;
    final showMessage =
        !isVideoMode &&
        !g.statusOk &&
        g.message.isNotEmpty &&
        g.status != GroupStatus.missingChinese &&
        g.status != GroupStatus.missingForeign;

    return Material(
      color: selected
          ? scheme.primaryContainer.withValues(alpha: 0.18)
          : Colors.transparent,
      child: InkWell(
        onTap: busy || isVideoMode ? null : () => onSelected(!selected),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: groupCheckboxValue,
                tristate: isVideoMode,
                onChanged: busy || videoTracks?.loading == true
                    ? null
                    : (value) => onSelected(value ?? true),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 6),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isVideoMode || g.statusOk
                      ? scheme.primaryContainer
                      : UiTokens.warningBg,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  isVideoMode ? Icons.movie_outlined : g.kindIcon,
                  size: 18,
                  color: isVideoMode || g.statusOk
                      ? scheme.primary
                      : UiTokens.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          isVideoMode && g.video != null
                              ? p.basename(g.video!.path)
                              : g.outputBase,
                          softWrap: true,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Tooltip(
                          message: isVideoMode
                              ? '显示容器内全部字幕轨；文本字幕可直接勾选抽取。'
                              : g.kindTooltip,
                          child: StatusBadge(
                            label: isVideoMode ? '视频' : g.kindLabel,
                            foreground: UiTokens.muted,
                            background: const Color(0xFFF0F3F7),
                            icon: Icons.info_outline_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    for (var i = 0; i < detailLines.length; i++) ...[
                      if (i > 0) const SizedBox(height: 3),
                      Row(
                        children: [
                          SizedBox(
                            width: 34,
                            child: Text(
                              detailLines[i].$1,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          Expanded(
                            child: Tooltip(
                              message: detailLines[i].$2 == '—'
                                  ? ''
                                  : detailLines[i].$2,
                              child: Text(
                                detailLines[i].$2,
                                maxLines: isVideoMode ? null : 1,
                                overflow: isVideoMode
                                    ? null
                                    : TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: detailLines[i].$2 == '—'
                                          ? UiTokens.warning
                                          : scheme.onSurfaceVariant,
                                    ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (isVideoMode) ...[
                      const SizedBox(height: 10),
                      _buildVideoTracks(context),
                    ],
                    if (showMessage) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: UiTokens.warningBg,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          g.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: UiTokens.warning),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              status,
            ],
          ),
        ),
      ),
    );
  }

  Widget _videoStatus(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = videoTracks!;
    if (state.loading) {
      return const StatusBadge(
        label: '读取中',
        icon: Icons.sync_rounded,
        foreground: UiTokens.muted,
        background: Color(0xFFF0F3F7),
      );
    }
    if (state.error != null) {
      return const StatusBadge(
        label: '探测失败',
        icon: Icons.priority_high_rounded,
        foreground: UiTokens.warning,
        background: UiTokens.warningBg,
      );
    }
    if (state.tracks.isEmpty) {
      return const StatusBadge(
        label: '无字幕轨',
        icon: Icons.subtitles_off_outlined,
        foreground: UiTokens.muted,
        background: Color(0xFFF0F3F7),
      );
    }
    if (state.selectedIds.isEmpty) {
      return const StatusBadge(
        label: '请选择',
        foreground: UiTokens.muted,
        background: Color(0xFFF0F3F7),
      );
    }
    return StatusBadge(
      label: '已选 ${state.selectedIds.length}',
      icon: Icons.check_rounded,
      foreground: scheme.primary,
      background: scheme.primaryContainer,
    );
  }

  Widget _buildVideoTracks(BuildContext context) {
    final state = videoTracks!;
    final scheme = Theme.of(context).colorScheme;
    if (state.loading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: UiTokens.subtle,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: UiTokens.border),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 9),
            Text('正在读取容器字幕轨…'),
          ],
        ),
      );
    }
    if (state.error != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.errorContainer.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          state.error!,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer),
        ),
      );
    }
    if (state.tracks.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: UiTokens.subtle,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: UiTokens.border),
        ),
        child: Text('容器内没有字幕轨。', style: Theme.of(context).textTheme.bodySmall),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: UiTokens.subtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: UiTokens.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < state.tracks.length; i++) ...[
            if (i > 0) const Divider(indent: 42),
            _buildTrackRow(context, state.tracks[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildTrackRow(BuildContext context, SubtitleTrackInfo track) {
    final scheme = Theme.of(context).colorScheme;
    final disabled = busy || track.isBitmap;
    final checked = videoTracks!.selectedIds.contains(track.id);
    final language = track.language.trim().isEmpty ? '未标记语言' : track.language;
    final flags = <String>[
      if (track.isDefault) '默认',
      if (track.isForced) '强制',
      if (track.isSdh) 'SDH',
    ];

    return InkWell(
      onTap: disabled ? null : () => onTrackSelected(track, !checked),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 7, 10, 7),
        child: Row(
          children: [
            Checkbox(
              value: checked,
              onChanged: disabled
                  ? null
                  : (value) => onTrackSelected(track, value ?? false),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '轨道 #${track.id} · $language',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: track.isBitmap
                                    ? UiTokens.muted
                                    : scheme.onSurface,
                              ),
                        ),
                      ),
                      if (flags.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          flags.join(' · '),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: UiTokens.muted),
                        ),
                      ],
                    ],
                  ),
                  if (track.title.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            StatusBadge(
              label: track.isBitmap ? '图像字幕 · ${track.codec}' : track.codec,
              foreground: track.isBitmap ? scheme.error : UiTokens.muted,
              background: track.isBitmap
                  ? scheme.errorContainer
                  : const Color(0xFFF0F3F7),
            ),
          ],
        ),
      ),
    );
  }
}

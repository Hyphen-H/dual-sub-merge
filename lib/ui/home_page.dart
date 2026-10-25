import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/app_workspace.dart';
import '../models/extract_pair_mode.dart';
import '../models/match_group.dart';
import '../models/merge_options.dart';
import '../models/process_mode.dart';
import '../models/track_role.dart';
import '../services/app_settings.dart';
import '../services/extract/extract_service.dart';
import '../services/extract/track_info.dart';
import '../services/extract/track_selector.dart';
import '../services/file_matcher.dart';
import '../services/language_tag_rename_service.dart';
import '../services/manual_group_edit.dart';
import '../services/merge_service.dart';
import '../services/process_mode_service.dart';
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

  /// Single unified input: a folder, an explicit file set, or both.
  String? _inputDir;
  Set<String> _inputFiles = {};
  List<MatchGroup> _groups = [];
  final _log = StringBuffer();
  final Map<String, _VideoTrackState> _videoTrackStates = {};

  /// Videos whose track list is currently expanded in extract mode. Probing is
  /// lazy: a video is only read when expanded or explicitly selected.
  final Set<String> _expandedVideos = {};

  /// Path-keyed manual overrides retained across rescan (session only).
  final Map<String, TrackRole> _manualRoles = {};
  bool _busy = false;
  bool _dragAnywhere = false;
  String _progress = '';
  int _progressCurrent = 0;
  int _progressTotal = 0;
  double? _progressFraction;
  bool _logExpanded = false;
  int _resIndex = 1; // 1080p
  bool _showIssuesOnly = false;
  AppWorkspace _workspace = AppWorkspace.subtitles;

  static final _videoExts = {'.mkv', '.mp4'};

  bool get _isExtractMode => _workspace == AppWorkspace.extract;

  List<MatchGroup> get _subtitleGroups => _groups
      .where(
        (g) =>
            g.kind == GroupKind.bilingualFile ||
            g.chinese != null ||
            g.foreign != null ||
            g.kind == GroupKind.pair,
      )
      .where((g) => _inputFiles.isEmpty || _groupTouchesFiles(g, _inputFiles))
      .toList();

  List<MatchGroup> get _videoGroups => _groups
      .where((g) => g.video != null)
      .where((g) => _inputFiles.isEmpty || _groupTouchesFiles(g, _inputFiles))
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
      _workspace = opts.workspace;
      _resIndex = ResolutionPreset.list.indexWhere(
        (e) => e.width == opts.playResX && e.height == opts.playResY,
      );
      if (_resIndex < 0) _resIndex = 1;
    });
  }

  Future<void> _persist() {
    _options.workspace = _workspace;
    return AppSettings.saveOptions(_options);
  }

  Future<void> _pickInputDir() async {
    final path = await FilePicker.getDirectoryPath(dialogTitle: '选择输入文件夹');
    if (path == null) return;
    setState(() {
      _inputDir = path;
      _inputFiles = {};
    });
    await AppSettings.saveLastDir(path);
    await AppSettings.saveLastInputFiles(const []);
    await _scan();
  }

  Future<void> _pickInputFiles() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: '选择字幕或视频文件',
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['ass', 'ssa', 'srt', 'vtt', 'mkv', 'mp4'],
    );
    final paths = result?.paths.whereType<String>().toList() ?? const [];
    if (paths.isEmpty) return;
    final dir = p.dirname(paths.first);
    setState(() {
      _inputDir = dir;
      _inputFiles = paths.map(_pathKey).toSet();
    });
    await AppSettings.saveLastDir(dir);
    await AppSettings.saveLastInputFiles(paths);
    await _scan();
  }

  void _setOutputMode(OutputDirMode mode) {
    setState(() => _options.outputDirMode = mode);
    _persist();
  }

  String? _resolvedOutputDir() {
    final dir = _inputDir;
    if (dir == null) return null;
    return _options.outputDirMode == OutputDirMode.source
        ? dir
        : p.join(dir, MergeOptions.mergedSubdirName);
  }

  Future<void> _scan({bool keepSelection = false}) async {
    final prevSelected = {for (final g in _groups) g.prefix: g.selected};
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

      if (_inputFiles.isNotEmpty) {
        for (final path in _inputFiles) {
          if (File(path).existsSync()) addFile(File(path));
        }
      } else if (_inputDir != null && Directory(_inputDir!).existsSync()) {
        final inputDir = _inputDir!;
        _log.writeln('[扫描] 目录 $inputDir');
        final files = await FileMatcher.listDirectoryFiles(
          Directory(inputDir),
          extractSubdir: _options.extractSubdir,
        );
        for (final file in files) {
          final ext = p.extension(file.path).toLowerCase();
          if (SubtitleLoader.exts.contains(ext) || _videoExts.contains(ext)) {
            addFile(file);
          }
        }
      }

      final candidates = filesByPath.values.toList();
      var skippedOutputs = 0;
      for (final f in candidates) {
        if (await FileMatcher.isSelfGeneratedOutput(f)) skippedOutputs++;
      }
      if (skippedOutputs > 0) {
        _log.writeln(
          '[扫描] 跳过 $skippedOutputs 个已合并成品（.chs+eng/jpn.ass / .chs.ass）',
        );
      }

      final all = await FileMatcher.scanFiles(
        candidates,
        extractSubdir: _options.extractSubdir,
      );
      ManualGroupEdit.applyOverrides(all, rolesByPath: _manualRoles);
      ProcessModeService.apply(all, _options.processMode);
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
        _syncVideoTrackStates(all);
        final n = _groups.where((e) => e.selected).length;
        _log.writeln(
          '[扫描] 完成 ${_groups.length} 组（全选 $n）@ 输入=${_inputDir ?? "-"}',
        );
      });
      if (all.isEmpty && skippedOutputs > 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 6),
              content: Text(
                '这 $skippedOutputs 个文件都是已合并的成品'
                '（.chs+eng/jpn.ass / .chs.ass），已跳过。请选择原始字幕所在文件夹。',
              ),
            ),
          );
        }
      }
    } catch (e) {
      _log.writeln('扫描失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('扫描失败: $e')));
      }
    } finally {
      setState(() {
        _busy = false;
        _progress = '';
        _progressCurrent = 0;
        _progressTotal = 0;
        _progressFraction = null;
      });
      if (mounted) {
        final hasSubtitles = _subtitleGroups.isNotEmpty;
        final hasVideos = _videoGroups.isNotEmpty;
        if (!hasSubtitles && hasVideos && !_isExtractMode) {
          await _setWorkspace(AppWorkspace.extract);
        } else if (hasSubtitles && !hasVideos && _isExtractMode) {
          await _setWorkspace(AppWorkspace.subtitles);
        }
      }
    }
  }

  void _syncVideoTrackStates(List<MatchGroup> groups) {
    final paths = groups
        .where((group) => group.video != null)
        .map((group) => group.video!.path)
        .toSet();
    _videoTrackStates.removeWhere((path, _) => !paths.contains(path));
    _expandedVideos.removeWhere((path) => !paths.contains(path));
    for (final path in paths) {
      _videoTrackStates.putIfAbsent(path, () => _VideoTrackState.unprobed());
    }
  }

  Future<void> _ensureVideoProbed(String path) async {
    final existing = _videoTrackStates[path];
    if (existing != null &&
        existing.probed &&
        !existing.loading &&
        existing.error == null) {
      return;
    }
    if (existing != null && existing.loading) return;

    setState(() => _videoTrackStates[path] = _VideoTrackState.loading());
    try {
      final tools = await ToolResolver.resolve(
        mkvToolNixDir: _options.mkvToolNixDir,
        ffmpegPath: _options.ffmpegPath,
        ffprobePath: _options.ffprobePath,
      );
      final tracks = await ExtractService(
        tools,
        _options,
      ).probeTracks(File(path));
      final selectedIds = _autoSelectedIds(tracks, _options.extractPairMode);
      if (!mounted) return;
      setState(() {
        _videoTrackStates[path] = _VideoTrackState.ready(
          tracks: tracks,
          selectedIds: selectedIds,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _videoTrackStates[path] = _VideoTrackState.failed('$e');
      });
    }
  }

  Set<int> _autoSelectedIds(
    List<SubtitleTrackInfo> tracks,
    ExtractPairMode mode,
  ) => TrackSelector.autoSelectedIds(tracks, mode: mode);

  Future<void> _toggleVideoExpanded(MatchGroup group) async {
    final path = group.video?.path;
    if (path == null) return;
    if (_expandedVideos.contains(path)) {
      setState(() => _expandedVideos.remove(path));
      return;
    }
    setState(() => _expandedVideos.add(path));
    await _ensureVideoProbed(path);
  }

  bool _isVideoGroupSelected(MatchGroup group) {
    final path = group.video?.path;
    return path != null &&
        (_videoTrackStates[path]?.selectedIds.isNotEmpty ?? false);
  }

  void _setVideoGroupSelected(MatchGroup group, bool selected) {
    final path = group.video?.path;
    if (path == null) return;
    final state = _videoTrackStates[path];
    if (state == null) return;
    if (!state.probed || state.loading || state.error != null) {
      () async {
        await _ensureVideoProbed(path);
        _applyVideoSelection(path, selected);
      }();
      return;
    }
    _applyVideoSelection(path, selected);
  }

  void _applyVideoSelection(String path, bool selected) {
    final state = _videoTrackStates[path];
    if (state == null || !state.probed || state.loading) return;
    setState(() {
      state.selectedIds
        ..clear()
        ..addAll(
          selected
              ? _autoSelectedIds(state.tracks, _options.extractPairMode)
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
    if (state == null ||
        !state.probed ||
        state.loading ||
        state.error != null ||
        track.isBitmap) {
      return;
    }
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
    if (_isExtractMode) {
      _selectAllVideos(value);
      return;
    }
    setState(() {
      for (final g in _visibleGroups(_subtitleGroups, videoMode: false)) {
        g.selected = value;
      }
    });
  }

  Future<void> _selectAllVideos(bool value) async {
    if (!value) {
      setState(() {
        for (final state in _videoTrackStates.values) {
          state.selectedIds.clear();
        }
      });
      return;
    }
    final targets = _visibleGroups(_videoGroups, videoMode: true);
    if (targets.isEmpty) return;
    setState(() => _busy = true);
    try {
      for (final g in targets) {
        final path = g.video?.path;
        if (path == null) continue;
        await _ensureVideoProbed(path);
        final state = _videoTrackStates[path];
        if (state == null ||
            !state.probed ||
            state.loading ||
            state.error != null) {
          continue;
        }
        state.selectedIds
          ..clear()
          ..addAll(_autoSelectedIds(state.tracks, _options.extractPairMode));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clearList() {
    setState(() {
      _groups = [];
      _videoTrackStates.clear();
      _expandedVideos.clear();
      _manualRoles.clear();
      _showIssuesOnly = false;
    });
  }

  void _onManualRole(MatchGroup group, String filePath, TrackRole role) {
    ManualGroupEdit.setFileRole(group, filePath, role);
    ManualGroupEdit.recordRole(_manualRoles, filePath, role);
    ManualGroupEdit.syncRolesFromGroup(_manualRoles, group);
    ProcessModeService.apply([group], _options.processMode);
    setState(() {});
  }

  Future<void> _setProcessMode(ProcessMode mode) async {
    setState(() => _options.processMode = mode);
    ProcessModeService.apply(_groups, mode);
    await _persist();
  }

  Future<void> _setWorkspace(AppWorkspace workspace) async {
    if (_busy || _workspace == workspace) return;
    setState(() {
      _workspace = workspace;
      _showIssuesOnly = false;
      if (workspace == AppWorkspace.subtitles) {
        ProcessModeService.apply(_groups, _options.processMode);
      }
    });
    await _persist();
  }

  Future<void> _setExtractPairMode(ExtractPairMode mode) async {
    if (_options.extractPairMode == mode) return;
    final previous = _options.extractPairMode;
    setState(() {
      _options.extractPairMode = mode;
      for (final state in _videoTrackStates.values) {
        if (!state.probed || state.loading || state.error != null) continue;
        final previousAuto = _autoSelectedIds(state.tracks, previous);
        if (!setEquals(state.selectedIds, previousAuto)) continue;
        state.selectedIds
          ..clear()
          ..addAll(_autoSelectedIds(state.tracks, mode));
      }
    });
    await _persist();
  }

  Future<void> _renameOnly() async {
    if (_inputDir == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先选择输入文件夹')));
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
        inputDir: Directory(_inputDir!),
        groups: selected,
        overwrite: _options.overwrite,
      );
      _log
        ..writeln('—— 仅改名 ——')
        ..writeln(r.logs.join('\n'))
        ..writeln(
          '完成 ${r.renamedCount}，跳过 ${r.skippedCount}，失败 ${r.failCount}',
        );
      await _syncExplicitInputFiles(selected);
      if (mounted) setState(() {});
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
    if (_inputDir == null && _inputFiles.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先拖入或选择视频')));
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
    final probedTracks = <String, List<SubtitleTrackInfo>>{
      for (final entry in _videoTrackStates.entries)
        if (entry.value.probed &&
            !entry.value.loading &&
            entry.value.error == null)
          entry.key: entry.value.tracks,
    };
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
      probeCache: probedTracks,
    );
    try {
      final result = await service.extractOnly(
        Directory(_inputDir ?? p.dirname(sourceGroups.first.video!.path)),
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
      await _mergeExtractedOutputs(result.outputs);
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
    if (_inputDir == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先选择或拖入输入')));
      return;
    }
    final outPath = _resolvedOutputDir();
    if (outPath == null || outPath.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先选择输入文件夹')));
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
    ProcessModeService.apply(_subtitleGroups, _options.processMode);
    await _persist();

    final mode = _options.processMode;
    setState(() {
      _busy = true;
      _progress = '${mode.workingLabel}中…';
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
        Directory(_inputDir!),
        outputDir: Directory(outPath),
        sourceGroups: sourceGroups,
      );
      _log
        ..writeln('—— 完成（${mode.label}）——')
        ..writeln('成功 ${result.successCount} / 失败 ${result.failCount}')
        ..writeln('双语转换: ${result.convertedBilingual}')
        ..writeln('中文转换: ${result.convertedChinese}')
        ..writeln('删除致谢行: ${result.removedCredits}')
        ..writeln(result.logs.join('\n'));
      if (result.skippedBilingual.isNotEmpty) {
        _log.writeln('${mode.workingLabel}无法处理已跳过:');
        for (final s in result.skippedBilingual) {
          _log.writeln('  - $s');
        }
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(mode.skipDialogTitle),
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
        await _syncExplicitInputFiles(sourceGroups);
      }
      if (mounted) setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '完成：成功 ${result.successCount}，失败 ${result.failCount}'
              '${result.convertedChinese > 0 ? '，中文化 ${result.convertedChinese}' : ''}'
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

    final automatic = TrackSelector.autoSelect(
      tracks,
      mode: _options.extractPairMode,
    );
    SubtitleTrackInfo? zh = automatic.chinese;
    SubtitleTrackInfo? en = automatic.foreign;
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

  /// Window-wide drop target: folders, subtitle files and videos are all accepted
  /// and routed to the single input, whatever the user dropped and however many.
  Future<void> _onDropAnywhere(DropDoneDetails details) async {
    if (_busy) {
      _log.writeln('拖入被忽略：正在处理中');
      return;
    }
    final paths = details.files
        .map((f) => f.path)
        .where((e) => e.isNotEmpty)
        .toList();
    if (paths.isEmpty) return;

    final dirs = <String>[];
    final files = <String>{};
    var subtitles = 0;
    var videos = 0;
    var rejected = 0;

    for (final path in paths) {
      final type = FileSystemEntity.typeSync(path);
      if (type == FileSystemEntityType.directory) {
        dirs.add(path);
        continue;
      }
      if (type != FileSystemEntityType.file) {
        rejected++;
        continue;
      }
      final ext = p.extension(path).toLowerCase();
      if (SubtitleLoader.exts.contains(ext)) {
        files.add(_pathKey(path));
        subtitles++;
      } else if (_videoExts.contains(ext)) {
        files.add(_pathKey(path));
        videos++;
      } else {
        rejected++;
      }
    }

    if (dirs.isEmpty && files.isEmpty) {
      _log.writeln('拖入 ${paths.length} 项，但没有任何字幕或视频文件');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('未识别到字幕或视频文件（支持 ass/ssa/srt/vtt/mkv/mp4）'),
          ),
        );
      }
      return;
    }

    // One folder wins outright; several collapse to their common parent so
    // dropping sibling season folders still scans both.
    final rootDir = dirs.isEmpty ? p.dirname(paths.first) : _commonParent(dirs);
    if (rootDir == null || !Directory(rootDir).existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法识别拖入路径')));
      }
      return;
    }

    // A dropped folder already covers everything inside it.
    final explicitFiles = dirs.isEmpty ? files : <String>{};
    setState(() {
      _inputDir = rootDir;
      _inputFiles = explicitFiles;
    });
    await AppSettings.saveLastDir(rootDir);
    await AppSettings.saveLastInputFiles(explicitFiles);

    final parts = <String>[
      if (dirs.isNotEmpty) '文件夹 ${dirs.length}',
      if (subtitles > 0) '字幕 $subtitles',
      if (videos > 0) '视频 $videos',
      if (rejected > 0) '忽略 $rejected',
    ];
    _log.writeln(
      '拖入输入: ${paths.map(p.basename).join(", ")} → ${parts.join("+")}',
    );
    await _scan();

    if (explicitFiles.isNotEmpty) {
      setState(() {
        for (final g in _groups) {
          g.selected = _groupTouchesFiles(g, explicitFiles);
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

  /// Deepest directory containing every path, or null when they span drives.
  static String? _commonParent(List<String> paths) {
    var parts = p.split(p.normalize(paths.first));
    for (final path in paths.skip(1)) {
      final other = p.split(p.normalize(path));
      var i = 0;
      while (i < parts.length &&
          i < other.length &&
          p.equals(parts[i], other[i])) {
        i++;
      }
      parts = parts.sublist(0, i);
      if (parts.isEmpty) return null;
    }
    final joined = p.joinAll(parts);
    return joined.isEmpty ? null : joined;
  }

  Widget _pathCard({
    required String label,
    required String pathText,
    required String hint,
    required IconData icon,
    required List<Widget> trailing,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final hasPath = pathText != '未选择输入';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: UiTokens.subtle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: UiTokens.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: UiTokens.muted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(label, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hint,
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
                    pathText,
                    softWrap: true,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: hasPath ? scheme.onSurface : UiTokens.muted,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ...trailing,
        ],
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

  Future<void> _syncExplicitInputFiles(Iterable<MatchGroup> groups) async {
    if (_inputFiles.isEmpty) return;
    final paths = <String>{};
    for (final group in groups) {
      for (final file in [
        group.chinese?.file,
        group.foreign?.file,
        group.bilingualSource,
        group.video,
      ]) {
        if (file != null && file.existsSync()) paths.add(_pathKey(file.path));
      }
    }
    setState(() => _inputFiles = paths);
    await AppSettings.saveLastInputFiles(paths);
  }

  /// Fold freshly extracted subtitle files into the existing video groups
  /// instead of rescanning the whole input folder.
  Future<void> _mergeExtractedOutputs(Iterable<String> outputPaths) async {
    final files = outputPaths
        .map(File.new)
        .where((file) => file.existsSync())
        .toList();
    if (files.isEmpty) return;
    final scanned = await FileMatcher.scanFiles(
      files,
      extractSubdir: _options.extractSubdir,
    );
    final byPrefix = {for (final g in _groups) g.prefix: g};
    setState(() {
      for (final fresh in scanned) {
        final existing = byPrefix[fresh.prefix];
        if (existing == null) {
          _groups.add(fresh);
          byPrefix[fresh.prefix] = fresh;
          continue;
        }
        if (fresh.chinese != null) existing.chinese = fresh.chinese;
        if (fresh.foreign != null) existing.foreign = fresh.foreign;
        existing.foreignTag = fresh.foreignTag;
        FileMatcher.reevaluate(existing);
        ProcessModeService.apply([existing], _options.processMode);
      }
      if (_inputFiles.isNotEmpty) {
        _inputFiles.addAll(files.map((file) => _pathKey(file.path)));
      }
    });
    if (_inputFiles.isNotEmpty) {
      await AppSettings.saveLastInputFiles(_inputFiles);
    }
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
                          '字幕与抽轨',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (!compact)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: Text(
                '工作台',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: UiTokens.muted,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          SidebarNavItem(
            icon: Icons.subtitles_outlined,
            label: '字幕处理',
            selected: !_isExtractMode,
            compact: compact,
            onTap: () => _setWorkspace(AppWorkspace.subtitles),
          ),
          const SizedBox(height: 2),
          SidebarNavItem(
            icon: Icons.movie_filter_outlined,
            label: '视频抽轨',
            selected: _isExtractMode,
            compact: compact,
            onTap: () => _setWorkspace(AppWorkspace.extract),
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
                'v0.4.1',
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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compactSidebar = constraints.maxWidth < 1080;
          final compactPage = constraints.maxWidth < 1180;
          // Keep AnimatedContainer as the DropTarget's direct child: desktop_drop
          // reads its RenderBox to decide whether the cursor is over the window,
          // and a plain full-size RenderBox is what that bounds check expects.
          return DropTarget(
            onDragEntered: (_) {
              if (_busy) return;
              _log.writeln('[拖放] 进入窗口');
              setState(() => _dragAnywhere = true);
            },
            onDragExited: (_) {
              _log.writeln('[拖放] 离开窗口');
              if (!_dragAnywhere) return;
              setState(() => _dragAnywhere = false);
            },
            onDragDone: (d) {
              _log.writeln('[拖放] 投放 ${d.files.length} 项');
              if (_dragAnywhere) setState(() => _dragAnywhere = false);
              _onDropAnywhere(d);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              color: _dragAnywhere
                  ? scheme.primaryContainer.withValues(alpha: 0.35)
                  : Colors.transparent,
              child: Row(
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
                          child: _buildWorkbench(compact: compactPage),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputCard() {
    final pathText = _inputFiles.isNotEmpty
        ? '已选择 ${_inputFiles.length} 个文件${_inputDir == null ? '' : '，${_inputDir!}'}'
        : _inputDir ?? '未选择输入';
    return _pathCard(
      label: '输入来源',
      pathText: pathText,
      hint: '拖到窗口任意位置即可识别，字幕与视频可一起拖入',
      icon: Icons.input_rounded,
      trailing: [
        OutlinedButton.icon(
          onPressed: _busy ? null : _pickInputFiles,
          icon: const Icon(Icons.note_add_outlined, size: 17),
          label: const Text('文件'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _pickInputDir,
          icon: const Icon(Icons.folder_open_outlined, size: 17),
          label: const Text('文件夹'),
        ),
        const SizedBox(width: 8),
        FilledButton.tonalIcon(
          onPressed: _busy || _inputDir == null ? null : () => _scan(),
          icon: const Icon(Icons.refresh_rounded, size: 17),
          label: const Text('扫描'),
        ),
      ],
    );
  }

  Widget _buildOutputDirPicker() {
    return SegmentedButton<OutputDirMode>(
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: const [
        ButtonSegment(
          value: OutputDirMode.mergedSubdir,
          label: Text('./${MergeOptions.mergedSubdirName}'),
          icon: Icon(Icons.create_new_folder_outlined, size: 16),
        ),
        ButtonSegment(
          value: OutputDirMode.source,
          label: Text('./'),
          icon: Icon(Icons.folder_outlined, size: 16),
        ),
      ],
      selected: {_options.outputDirMode},
      onSelectionChanged: _busy
          ? null
          : (values) => _setOutputMode(values.first),
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
                                _VideoTrackState.unprobed()
                          : null;
                      return _GroupTile(
                        group: g,
                        selected: showVideoTracks
                            ? _isVideoGroupSelected(g)
                            : g.selected,
                        busy: _busy,
                        videoTracks: videoState,
                        videoExpanded:
                            videoState != null &&
                            _expandedVideos.contains(g.video!.path),
                        onVideoExpand: videoState == null
                            ? null
                            : () => _toggleVideoExpanded(g),
                        mode: _options.processMode,
                        onSelected: (value) {
                          if (showVideoTracks) {
                            _setVideoGroupSelected(g, value);
                          } else {
                            setState(() => g.selected = value);
                          }
                        },
                        onTrackSelected: (track, value) =>
                            _setVideoTrackSelected(g, track, value),
                        onRoleChanged: showVideoTracks
                            ? null
                            : (path, role) => _onManualRole(g, path, role),
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

  Widget _buildWorkbench({required bool compact}) {
    final mode = _options.processMode;
    final gap = compact ? 8.0 : 12.0;
    final extract = _isExtractMode;
    final list = extract ? _videoGroups : _subtitleGroups;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(title: extract ? '视频抽轨' : '字幕处理'),
        if (!extract) ...[
          SizedBox(height: compact ? 6 : 10),
          ProcessModePicker(
            mode: mode,
            enabled: !_busy,
            onChanged: _setProcessMode,
          ),
        ],
        SizedBox(height: compact ? 10 : 16),
        AppSurface(
          padding: EdgeInsets.all(compact ? 8 : 12),
          child: _buildInputCard(),
        ),
        SizedBox(height: gap),
        _buildActions(),
        SizedBox(height: gap),
        Expanded(
          child: _buildGroupList(
            groups: list,
            showVideoTracks: extract,
            emptyTitle: extract ? '尚未发现可处理的视频' : '尚未发现可处理的字幕',
            emptyHint: extract
                ? '将含字幕轨的视频或目录拖到窗口任意位置。\n抽出的字幕会出现在输入目录里，可切回「字幕处理」继续。'
                : '把字幕拖到窗口任意位置，或点上方按钮选择。\n视频请切换到左侧「视频抽轨」。',
            emptyIcon: extract
                ? Icons.video_file_outlined
                : Icons.subtitles_off_outlined,
          ),
        ),
        SizedBox(height: gap),
        _buildLogPanel(),
      ],
    );
  }

  Widget _buildActions() {
    final mode = _options.processMode;
    final extract = _isExtractMode;
    return AppSurface(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (extract)
            ExtractPairModePicker(
              mode: _options.extractPairMode,
              enabled: !_busy,
              onChanged: _setExtractPairMode,
            )
          else ...[
            _buildOutputDirPicker(),
            ResolutionPicker(
              index: _resIndex,
              enabled: !_busy,
              onChanged: (i) {
                _setResolutionIndex(i);
              },
            ),
            OptionCheck(
              label: '删除致谢',
              value: _options.removeCredits,
              tooltip: '用锚定正则删除「翻译:」「校对:」等致谢行',
              enabled: !_busy,
              onChanged: (v) async {
                setState(() => _options.removeCredits = v);
                await _persist();
              },
            ),
            OptionCheck(
              label: '标记语言改名',
              value: _options.tagLanguageOnMerge,
              tooltip: '无语言标记的源字幕将移入 chs-sub / eng-sub，并补上 .chs / .eng',
              enabled: !_busy,
              onChanged: (v) async {
                setState(() => _options.tagLanguageOnMerge = v);
                await _persist();
              },
            ),
            OptionCheck(
              label: 'HDR',
              value: _options.hdrSubtitle,
              tooltip: _options.hdrSubtitle
                  ? '输出 HDRipad 样式'
                  : '输出 SDR 样式（正文亮度 255 纯白）',
              enabled: !_busy,
              onChanged: (v) async {
                setState(() => _options.hdrSubtitle = v);
                await _persist();
              },
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _renameOnly,
              icon: const Icon(Icons.drive_file_rename_outline, size: 17),
              label: const Text('仅改名'),
            ),
          ],
          FilledButton.icon(
            onPressed: _busy ? null : (extract ? _extractVideos : _run),
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    extract ? Icons.download_rounded : Icons.play_arrow_rounded,
                    size: 19,
                  ),
            label: Text(
              _busy
                  ? (extract ? '抽取中' : '处理中')
                  : extract
                  ? '开始抽轨'
                  : _options.tagLanguageOnMerge
                  ? mode.actionLabelWithRename
                  : mode.actionLabel,
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoTrackState {
  _VideoTrackState({
    required this.loading,
    required this.tracks,
    required this.selectedIds,
    required this.probed,
    this.error,
  });

  factory _VideoTrackState.unprobed() => _VideoTrackState(
    loading: false,
    tracks: const [],
    selectedIds: <int>{},
    probed: false,
  );

  factory _VideoTrackState.loading() => _VideoTrackState(
    loading: true,
    tracks: const [],
    selectedIds: <int>{},
    probed: false,
  );

  factory _VideoTrackState.ready({
    required List<SubtitleTrackInfo> tracks,
    required Set<int> selectedIds,
  }) => _VideoTrackState(
    loading: false,
    tracks: tracks,
    selectedIds: selectedIds,
    probed: true,
  );

  factory _VideoTrackState.failed(String error) => _VideoTrackState(
    loading: false,
    tracks: const [],
    selectedIds: <int>{},
    probed: true,
    error: error,
  );

  final bool loading;
  final List<SubtitleTrackInfo> tracks;
  final Set<int> selectedIds;

  /// Whether the container was already probed (or failed probing).
  final bool probed;
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
    this.videoExpanded = false,
    this.onVideoExpand,
    this.mode = ProcessMode.merge,
    this.onRoleChanged,
  });

  final MatchGroup group;
  final bool selected;
  final bool busy;
  final ValueChanged<bool> onSelected;
  final void Function(SubtitleTrackInfo track, bool selected) onTrackSelected;
  final _VideoTrackState? videoTracks;
  final bool videoExpanded;
  final VoidCallback? onVideoExpand;
  final ProcessMode mode;
  final void Function(String filePath, TrackRole role)? onRoleChanged;

  @override
  Widget build(BuildContext context) {
    final g = group;
    final scheme = Theme.of(context).colorScheme;
    final isVideoMode = videoTracks != null;
    final canEdit = !isVideoMode && !busy && onRoleChanged != null;

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
                  isVideoMode ? Icons.movie_outlined : mode.icon,
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
                        if (isVideoMode)
                          Tooltip(
                            message: '显示容器内全部字幕轨；文本字幕可直接勾选抽取。',
                            child: const StatusBadge(
                              label: '视频',
                              foreground: UiTokens.muted,
                              background: Color(0xFFF0F3F7),
                              icon: Icons.info_outline_rounded,
                            ),
                          )
                        else
                          _buildKindChip(context),
                      ],
                    ),
                    const SizedBox(height: 7),
                    if (isVideoMode)
                      _detailRow(
                        context,
                        label: '视频',
                        name: g.video == null ? '—' : p.basename(g.video!.path),
                      )
                    else if (g.kind == GroupKind.bilingualFile)
                      _subtitleSlotRow(
                        context,
                        label: '源',
                        file: g.bilingualSource,
                        role: TrackRole.unknown,
                        canEdit: canEdit,
                        allowRoleEdit: false,
                      )
                    else ...[
                      _subtitleSlotRow(
                        context,
                        label: '中',
                        file: g.chinese?.file,
                        role: g.chinese?.role ?? TrackRole.unknown,
                        canEdit: canEdit && g.chinese != null,
                        allowRoleEdit: true,
                      ),
                      const SizedBox(height: 3),
                      _subtitleSlotRow(
                        context,
                        label: '外',
                        file: g.foreign?.file,
                        role: g.foreign?.role ?? TrackRole.unknown,
                        canEdit: canEdit && g.foreign != null,
                        allowRoleEdit: true,
                      ),
                      if (g.video != null) ...[
                        const SizedBox(height: 3),
                        _detailRow(
                          context,
                          label: '视频',
                          name: p.basename(g.video!.path),
                        ),
                      ],
                    ],
                    if (isVideoMode) ...[
                      const SizedBox(height: 10),
                      _buildVideoTracksToggle(context),
                      if (videoExpanded) ...[
                        const SizedBox(height: 8),
                        _buildVideoTracks(context),
                      ],
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

  Widget _buildKindChip(BuildContext context) {
    return Tooltip(
      message: '${mode.tooltip}\n由顶部“${mode.label}”统一控制',
      child: StatusBadge(
        label: mode.label,
        foreground: UiTokens.muted,
        background: const Color(0xFFF0F3F7),
        icon: mode.icon,
      ),
    );
  }

  Widget _detailRow(
    BuildContext context, {
    required String label,
    required String name,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 34,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: Tooltip(
            message: name == '—' ? '' : name,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: name == '—' ? UiTokens.warning : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _subtitleSlotRow(
    BuildContext context, {
    required String label,
    required File? file,
    required TrackRole role,
    required bool canEdit,
    required bool allowRoleEdit,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final name = file == null ? '—' : p.basename(file.path);
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: canEdit && allowRoleEdit ? scheme.primary : null,
      decoration: canEdit && allowRoleEdit ? TextDecoration.underline : null,
      decorationColor: scheme.primary.withValues(alpha: 0.45),
    );

    Widget labelWidget = Text(label, style: labelStyle);
    if (canEdit && allowRoleEdit && file != null && onRoleChanged != null) {
      labelWidget = PopupMenuButton<TrackRole>(
        tooltip: '标记语言：${role.label}',
        enabled: !busy,
        onSelected: (value) => onRoleChanged!(file.path, value),
        itemBuilder: (context) => [
          for (final r in TrackRole.values)
            CheckedPopupMenuItem(
              value: r,
              checked: role == r,
              child: Text(r.label),
            ),
        ],
        child: labelWidget,
      );
    }

    return Row(
      children: [
        SizedBox(width: 34, child: labelWidget),
        Expanded(
          child: Tooltip(
            message: name == '—' ? '' : name,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: name == '—' ? UiTokens.warning : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVideoTracksToggle(BuildContext context) {
    final state = videoTracks!;
    final scheme = Theme.of(context).colorScheme;
    final label = state.loading
        ? '正在读取字幕轨…'
        : !state.probed
        ? '展开并读取字幕轨'
        : videoExpanded
        ? '收起字幕轨'
        : '展开字幕轨（${state.tracks.length} 条）';
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: busy ? null : onVideoExpand,
        icon: Icon(
          state.loading
              ? Icons.sync_rounded
              : videoExpanded
              ? Icons.expand_less_rounded
              : Icons.expand_more_rounded,
          size: 18,
        ),
        label: Text(label),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 30),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: scheme.primary,
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
    if (!state.probed) {
      return const StatusBadge(
        label: '未探测',
        icon: Icons.info_outline_rounded,
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
    if (!state.probed && !state.loading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: UiTokens.subtle,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: UiTokens.border),
        ),
        child: Text('尚未读取字幕轨。', style: Theme.of(context).textTheme.bodySmall),
      );
    }
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
    final disabled = busy || track.isBitmap || !videoTracks!.probed;
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

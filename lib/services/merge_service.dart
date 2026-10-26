import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/match_group.dart';
import '../models/merge_options.dart';
import '../models/process_mode.dart';
import '../models/subtitle_cue.dart';
import '../models/track_role.dart';
import 'bilingual_convert_service.dart';
import 'chinese_convert_service.dart';
import 'bilingual_inline.dart';
import 'blacklist.dart';
import 'extract/extract_service.dart';
import 'extract/track_info.dart';
import 'extract/track_selector.dart';
import 'file_matcher.dart';
import 'language_from_name.dart';
import 'language_tag_rename_service.dart';
import 'parse/ass_writer.dart';
import 'parse/style_resolver.dart';
import 'parse/subtitle_loader.dart';
import 'process_mode_service.dart';
import 'text_pipeline.dart';
import 'tools/tool_resolver.dart';

class MergeProgress {
  MergeProgress({
    required this.current,
    required this.total,
    required this.message,
    this.done = false,
    this.fraction,
  });
  final int current;
  final int total;
  final String message;
  final bool done;
  final double? fraction;
}

class MergeResult {
  MergeResult({
    required this.successCount,
    required this.failCount,
    required this.removedCredits,
    required this.skippedBilingual,
    required this.convertedBilingual,
    required this.convertedChinese,
    required this.logs,
    required this.outputs,
  });

  final int successCount;
  final int failCount;
  final int removedCredits;
  final List<String> skippedBilingual;
  final int convertedBilingual;
  final int convertedChinese;
  final List<String> logs;
  final List<String> outputs;
}

class MergeService {
  MergeService({
    required this.options,
    this.onProgress,
    this.onConflict,
    this.onPickTracks,
    this.selectedPrefixes,
    this.selectedTrackIdsByVideo,
    this.probeCache,
  });

  final MergeOptions options;
  final void Function(MergeProgress progress)? onProgress;
  final Future<bool> Function(MatchGroup group)? onConflict;
  final Future<SelectedTracks?> Function(
    String videoPath,
    List<SubtitleTrackInfo> tracks,
    ExtractNeed need,
  )?
  onPickTracks;
  final Set<String>? selectedPrefixes;
  final Map<String, Set<int>>? selectedTrackIdsByVideo;

  /// Track lists the UI already probed, keyed by video path.
  final Map<String, List<SubtitleTrackInfo>>? probeCache;

  bool _isSelected(MatchGroup g) {
    if (selectedPrefixes == null) return true;
    return selectedPrefixes!.contains(g.prefix);
  }

  /// Extract subtitle tracks from selected video groups only (no merge).
  Future<MergeResult> extractOnly(
    Directory dir, {
    Iterable<MatchGroup>? sourceGroups,
  }) async {
    final logs = <String>[];
    final outputs = <String>[];
    var success = 0;
    var fail = 0;

    final tools = await ToolResolver.resolve(
      mkvToolNixDir: options.mkvToolNixDir,
      ffmpegPath: options.ffmpegPath,
      ffprobePath: options.ffprobePath,
    );
    logs.add(
      '工具: mkvextract=${tools.mkvextract ?? "无"} ffmpeg=${tools.ffmpeg ?? "无"}',
    );

    var groups =
        sourceGroups?.toList() ??
        await FileMatcher.scanDirectory(
          dir,
          extractSubdir: options.extractSubdir,
        );
    if (selectedPrefixes != null) {
      groups = groups.where(_isSelected).toList();
    }

    final explicitTrackSelection = selectedTrackIdsByVideo;
    final work = groups.where((g) {
      if (!_isSelected(g) || g.kind == GroupKind.bilingualFile) return false;
      if (g.video == null) return false;
      if (explicitTrackSelection != null) {
        return explicitTrackSelection[g.video!.path]?.isNotEmpty == true;
      }
      final needZh = g.chinese == null || g.chinese!.role != TrackRole.chinese;
      final needEn = g.foreign == null || g.foreign!.role != TrackRole.foreign;
      return needZh || needEn;
    }).toList();

    logs.add('待抽轨 ${work.length} 组');
    if (work.isEmpty) {
      logs.add('无需要抽轨的视频组');
      return MergeResult(
        successCount: 0,
        failCount: 0,
        removedCredits: 0,
        skippedBilingual: const [],
        convertedBilingual: 0,
        convertedChinese: 0,
        logs: logs,
        outputs: outputs,
      );
    }

    final extractor = ExtractService(tools, options)
      ..onNeedUserPick = onPickTracks;
    FolderTrackChoice? folderChoice;

    for (var i = 0; i < work.length; i++) {
      final g = work[i];
      final videoName = p.basename(g.video!.path);
      final needZh = g.chinese == null || g.chinese!.role != TrackRole.chinese;
      final needEn = g.foreign == null || g.foreign!.role != TrackRole.foreign;

      onProgress?.call(
        MergeProgress(
          current: i + 1,
          total: work.length,
          message: '抽取: $videoName',
          fraction: 0,
        ),
      );

      try {
        extractor.onTrackProgress = (trackIdx, trackTotal, track) {
          onProgress?.call(
            MergeProgress(
              current: i + 1,
              total: work.length,
              message: '抽取 $videoName · 轨道 #${track.id}',
              fraction: trackTotal == 0 ? 0 : (trackIdx - 1) / trackTotal,
            ),
          );
        };
        extractor.onExtractionProgress =
            (trackIdx, trackTotal, track, trackFraction) {
              final videoFraction = trackTotal == 0
                  ? trackFraction
                  : ((trackIdx - 1) + trackFraction) / trackTotal;
              onProgress?.call(
                MergeProgress(
                  current: i + 1,
                  total: work.length,
                  message:
                      '抽取 $videoName · 轨道 #${track.id} · '
                      '${(trackFraction * 100).round()}%',
                  fraction: videoFraction.clamp(0, 1),
                ),
              );
            };
        if (explicitTrackSelection != null) {
          final selectedIds =
              explicitTrackSelection[g.video!.path] ?? const <int>{};
          final tracks =
              probeCache?[g.video!.path] ??
              await extractor.probeTracks(g.video!);
          final selectedTracks = tracks
              .where((track) => selectedIds.contains(track.id))
              .toList();
          final result = await extractor.extractSelectedTracks(
            video: g.video!,
            tracks: selectedTracks,
          );
          logs.add('[${g.outputBase}] ${result.log}');
          outputs.addAll(result.files.map((file) => file.path));
          if (result.files.isEmpty) {
            fail++;
          } else {
            success++;
          }
          continue;
        }

        extractor.onNeedUserPick = (path, tracks, need) async {
          if (folderChoice != null) {
            final auto = TrackSelector.autoSelect(
              tracks,
              mode: options.extractPairMode,
            );
            return SelectedTracks(
              chinese: folderChoice!.pickChinese?.call(tracks) ?? auto.chinese,
              foreign: folderChoice!.pickForeign?.call(tracks) ?? auto.foreign,
            );
          }
          final picked = await onPickTracks?.call(path, tracks, need);
          if (picked != null) {
            final zhId = picked.chinese?.id;
            final enId = picked.foreign?.id;
            folderChoice = FolderTrackChoice()
              ..pickChinese = zhId == null
                  ? null
                  : (ts) {
                      try {
                        return ts.firstWhere((t) => t.id == zhId);
                      } catch (_) {
                        return TrackSelector.autoSelect(
                          ts,
                          mode: options.extractPairMode,
                        ).chinese;
                      }
                    }
              ..pickForeign = enId == null
                  ? null
                  : (ts) {
                      try {
                        return ts.firstWhere((t) => t.id == enId);
                      } catch (_) {
                        return TrackSelector.autoSelect(
                          ts,
                          mode: options.extractPairMode,
                        ).foreign;
                      }
                    };
          }
          return picked;
        };

        final result = await extractor.extractForVideo(
          video: g.video!,
          need: ExtractNeed(needChinese: needZh, needForeign: needEn),
          folderChoice: folderChoice,
        );
        logs.add('[${g.outputBase}] ${result.log}');
        var got = false;
        if (result.chinese != null) {
          outputs.add(result.chinese!.path);
          got = true;
        }
        if (result.foreign != null) {
          outputs.add(result.foreign!.path);
          got = true;
        }
        if (got) {
          success++;
        } else {
          fail++;
        }
      } catch (e) {
        fail++;
        logs.add('[${g.outputBase}] 抽取失败: $e');
      }
    }

    onProgress?.call(
      MergeProgress(
        current: work.length,
        total: work.length,
        message: '抽轨完成',
        done: true,
        fraction: 1,
      ),
    );

    return MergeResult(
      successCount: success,
      failCount: fail,
      removedCredits: 0,
      skippedBilingual: const [],
      convertedBilingual: 0,
      convertedChinese: 0,
      logs: logs,
      outputs: outputs,
    );
  }

  Future<MergeResult> run(
    Directory dir, {
    Directory? outputDir,
    Iterable<MatchGroup>? sourceGroups,
  }) async {
    final logs = <String>[];
    final skippedBilingual = <String>[];
    final outputs = <String>[];
    var success = 0;
    var fail = 0;
    var removedCredits = 0;
    var convertedBilingual = 0;
    var convertedChinese = 0;
    final mode = options.processMode;
    final hdrSubtitle = options.hdrSubtitle;
    final styles = StyleResolver.resolve(options);
    if (sourceGroups != null) {
      for (final group in sourceGroups) {
        ProcessModeService.selectForeignForMode(group, mode);
      }
    }

    final outDir = outputDir ?? dir;
    if (!outDir.existsSync()) {
      await outDir.create(recursive: true);
    }
    logs.add('输出目录: ${outDir.path}');

    final tools = await ToolResolver.resolve(
      mkvToolNixDir: options.mkvToolNixDir,
      ffmpegPath: options.ffmpegPath,
      ffprobePath: options.ffprobePath,
    );
    logs.add(
      '工具: mkvextract=${tools.mkvextract ?? "无"} ffmpeg=${tools.ffmpeg ?? "无"}',
    );

    var groups =
        sourceGroups?.toList() ??
        await FileMatcher.scanDirectory(
          dir,
          extractSubdir: options.extractSubdir,
        );
    if (selectedPrefixes != null) {
      groups = groups.where(_isSelected).toList();
    }
    logs.add('待处理 ${groups.length} 组');

    if (options.tagLanguageOnMerge) {
      onProgress?.call(
        MergeProgress(current: 0, total: groups.length, message: '标记语言改名…'),
      );
      final rename = await LanguageTagRenameService().renameGroups(
        inputDir: dir,
        groups: groups,
        overwrite: options.overwrite,
      );
      logs.addAll(rename.logs);
      logs.add(
        '语言标记改名: 完成 ${rename.renamedCount}，跳过 ${rename.skippedCount}，失败 ${rename.failCount}',
      );
    }

    for (final g in groups) {
      if (!_isSelected(g)) continue;
      if (ProcessModeService.isReady(g, mode)) continue;
      if ((mode != ProcessMode.merge && mode != ProcessMode.dubMerge) ||
          g.kind == GroupKind.bilingualFile) {
        continue;
      }
      if (onConflict != null) {
        final ok = await onConflict!(g);
        if (ok) FileMatcher.reevaluate(g);
      }
    }

    final blacklist = BlacklistFilter(options.blacklistRules);
    final converter = BilingualConvertService(options);
    final chineseConverter = ChineseConvertService(options);
    final workList = groups.where(_isSelected).toList();

    for (var i = 0; i < workList.length; i++) {
      final g = workList[i];
      onProgress?.call(
        MergeProgress(
          current: i + 1,
          total: workList.length,
          message: '${mode.workingLabel}: ${g.outputBase}',
        ),
      );

      // —— 中文转换：单中字幕 → .chs.ass ——
      if (mode == ProcessMode.chineseConvert) {
        final source = ProcessModeService.resolveSource(g);
        if (source == null) {
          fail++;
          logs.add('[${g.outputBase}] 跳过: ${g.message}');
          continue;
        }
        try {
          final r = await chineseConverter.convertFile(
            source: source,
            outDir: outDir,
            displayPrefix: g.displayPrefix,
          );
          if (r.ok) {
            g.status = GroupStatus.done;
            g.outputPath = r.outputPath;
            outputs.add(r.outputPath!);
            success++;
            convertedChinese++;
            removedCredits += r.removedCredits;
            logs.add('[${g.outputBase}] 中文转换完成: ${r.message}');
          } else {
            g.status = GroupStatus.bilingualInline;
            g.message = r.message;
            skippedBilingual.add(source.path);
            fail++;
            logs.add('[${g.outputBase}] 中文转换跳过: ${r.message}');
          }
        } catch (e) {
          fail++;
          g.status = GroupStatus.failed;
          g.message = '$e';
          logs.add('[${g.outputBase}] 中文转换失败: $e');
        }
        continue;
      }

      // —— 样式转换：任何字幕文件都按 \N 双语拆 ——
      if (mode == ProcessMode.styleConvert) {
        final source = ProcessModeService.resolveSource(g);
        if (source == null) {
          fail++;
          logs.add('[${g.outputBase}] 跳过: ${g.message}');
          continue;
        }
        try {
          final r = await converter.convertFile(
            source: source,
            outDir: outDir,
            displayPrefix: g.displayPrefix,
          );
          if (r.ok) {
            g.status = GroupStatus.done;
            g.outputPath = r.outputPath;
            outputs.add(r.outputPath!);
            success++;
            convertedBilingual++;
            removedCredits += r.removedCredits;
            logs.add('[${g.outputBase}] 样式转换完成: ${r.message}');
          } else {
            g.status = GroupStatus.bilingualInline;
            g.message = r.message;
            skippedBilingual.add(source.path);
            fail++;
            logs.add('[${g.outputBase}] 样式转换跳过: ${r.message}');
          }
        } catch (e) {
          fail++;
          g.status = GroupStatus.failed;
          g.message = '$e';
          logs.add('[${g.outputBase}] 样式转换失败: $e');
        }
        continue;
      }

      // —— bilingual file convert ——
      if (g.kind == GroupKind.bilingualFile && g.bilingualSource != null) {
        if (mode == ProcessMode.dubMerge) {
          fail++;
          g.status = GroupStatus.conflict;
          g.message = '中英配需要中文 + Dubtitle 字幕';
          logs.add('[${g.outputBase}] 跳过: ${g.message}');
          continue;
        }
        try {
          final r = await converter.convertFile(
            source: g.bilingualSource!,
            outDir: outDir,
            displayPrefix: g.displayPrefix,
          );
          if (r.ok) {
            g.status = GroupStatus.done;
            g.outputPath = r.outputPath;
            outputs.add(r.outputPath!);
            success++;
            convertedBilingual++;
            removedCredits += r.removedCredits;
            logs.add('[${g.outputBase}] 双语转换完成: ${r.message}');
          } else {
            g.status = GroupStatus.bilingualInline;
            g.message = r.message;
            skippedBilingual.add(g.bilingualSource!.path);
            fail++;
            logs.add('[${g.outputBase}] 双语转换跳过: ${r.message}');
          }
        } catch (e) {
          fail++;
          g.status = GroupStatus.failed;
          g.message = '$e';
          logs.add('[${g.outputBase}] 双语转换失败: $e');
        }
        continue;
      }

      if (mode == ProcessMode.jpMerge &&
          !ProcessModeService.hasJapaneseForeign(g)) {
        fail++;
        g.status = GroupStatus.missingForeign;
        g.message = '外文不是日文';
        logs.add('[${g.outputBase}] 跳过: 外文不是日文');
        continue;
      }
      if (mode == ProcessMode.dubMerge &&
          !ProcessModeService.hasDubtitleForeign(g)) {
        fail++;
        g.status = GroupStatus.missingForeign;
        g.message = '外文不是 Dubtitle';
        logs.add('[${g.outputBase}] 跳过: 外文不是 Dubtitle');
        continue;
      }

      if (!ProcessModeService.isReady(g, mode)) {
        logs.add('[${g.outputBase}] 跳过: ${g.message}');
        fail++;
        continue;
      }

      try {
        final zhDoc = await SubtitleLoader.load(g.chinese!.file);
        final enDoc = await SubtitleLoader.load(g.foreign!.file);

        // If one side is actually \\N dual, convert that file instead of skipping pair
        final zhBi = BilingualInlineDetector.isBilingualInline(zhDoc.cues);
        final enBi = BilingualInlineDetector.isBilingualInline(enDoc.cues);
        if (zhBi || enBi) {
          final biFile = zhBi ? g.chinese!.file : g.foreign!.file;
          final r = await converter.convertFile(
            source: biFile,
            outDir: outDir,
            displayPrefix: g.displayPrefix,
          );
          if (r.ok) {
            g.status = GroupStatus.done;
            g.outputPath = r.outputPath;
            outputs.add(r.outputPath!);
            success++;
            convertedBilingual++;
            removedCredits += r.removedCredits;
            logs.add('[${g.outputBase}] 配对中检出双语，已转换: ${r.message}');
          } else {
            g.status = GroupStatus.bilingualInline;
            g.message = r.message;
            skippedBilingual.add(biFile.path);
            fail++;
            logs.add('[${g.outputBase}] 双语无法转换: ${r.message}');
          }
          continue;
        }

        var zhCues = zhDoc.cues;
        var enCues = enDoc.cues;
        if (options.removeCredits) {
          final zr = blacklist.filter(zhCues);
          final er = blacklist.filter(enCues);
          zhCues = zr.$1;
          enCues = er.$1;
          removedCredits += zr.$2 + er.$2;
        }

        final outCues = <SubtitleCue>[
          ...zhCues.map(
            (c) => TextPipeline.process(
              c,
              TrackRole.chinese,
              hdr: hdrSubtitle,
              names: styles.names,
              treatAn8AsAnnotation: options.an8AsAnnotation,
            ),
          ),
          ...enCues.map(
            (c) => TextPipeline.process(
              c,
              TrackRole.foreign,
              hdr: hdrSubtitle,
              names: styles.names,
              treatAn8AsAnnotation: options.an8AsAnnotation,
            ),
          ),
        ];

        final detectedForeignTag =
            g.foreignTag ??
            LanguageFromName.explicitOutputFileTag(g.foreign!.file.path) ??
            LanguageFromName.tagFromContent(enCues.map((c) => c.rawText)) ??
            'eng';
        final foreignTag = mode == ProcessMode.jpMerge
            ? 'jpn'
            : mode == ProcessMode.dubMerge
            ? 'eng_dub'
            : detectedForeignTag == 'eng_dub'
            ? 'eng'
            : detectedForeignTag;
        final outName = '${g.outputBase}.chs+$foreignTag.ass';
        final outPath = p.join(outDir.path, outName);
        if (!options.overwrite && File(outPath).existsSync()) {
          logs.add('[${g.outputBase}] 已存在，跳过: $outName');
          fail++;
          continue;
        }

        await AssWriter.write(
          path: outPath,
          cues: outCues,
          options: options,
          title: g.outputBase,
        );
        g.outputPath = outPath;
        g.status = GroupStatus.done;
        outputs.add(outPath);
        success++;
        logs.add('[${g.outputBase}] 完成 -> $outName (${outCues.length} 条)');
      } catch (e) {
        fail++;
        g.status = GroupStatus.failed;
        g.message = '$e';
        logs.add('[${g.outputBase}] 失败: $e');
      }
    }

    onProgress?.call(
      MergeProgress(
        current: workList.length,
        total: workList.length,
        message: '完成',
        done: true,
      ),
    );

    return MergeResult(
      successCount: success,
      failCount: fail,
      removedCredits: removedCredits,
      skippedBilingual: skippedBilingual.toSet().toList(),
      convertedBilingual: convertedBilingual,
      convertedChinese: convertedChinese,
      logs: logs,
      outputs: outputs,
    );
  }

  Future<MergeResult> runSelectedModes(
    Directory dir, {
    Directory? outputDir,
    Iterable<MatchGroup>? sourceGroups,
    required Iterable<ProcessMode> modes,
  }) async {
    final selected = modes.where((mode) => mode.isPairingMode).toList();
    if (selected.length <= 1) {
      if (selected.isNotEmpty) {
        options.processMode = selected.first;
        if (sourceGroups != null) {
          ProcessModeService.apply(sourceGroups.toList(), selected.first);
        }
      }
      return run(dir, outputDir: outputDir, sourceGroups: sourceGroups);
    }

    final originalMode = options.processMode;
    var successCount = 0;
    var failCount = 0;
    var removedCredits = 0;
    var convertedBilingual = 0;
    var convertedChinese = 0;
    final skippedBilingual = <String>[];
    final logs = <String>[];
    final outputs = <String>[];
    try {
      for (final mode in selected) {
        options.processMode = mode;
        if (sourceGroups != null) {
          ProcessModeService.apply(sourceGroups.toList(), mode);
        }
        final result = await run(
          dir,
          outputDir: outputDir,
          sourceGroups: sourceGroups,
        );
        successCount += result.successCount;
        failCount += result.failCount;
        removedCredits += result.removedCredits;
        convertedBilingual += result.convertedBilingual;
        convertedChinese += result.convertedChinese;
        skippedBilingual.addAll(result.skippedBilingual);
        logs
          ..add('—— ${mode.label} ——')
          ..addAll(result.logs);
        outputs.addAll(result.outputs);
      }
    } finally {
      options.processMode = originalMode;
    }
    return MergeResult(
      successCount: successCount,
      failCount: failCount,
      removedCredits: removedCredits,
      skippedBilingual: skippedBilingual,
      convertedBilingual: convertedBilingual,
      convertedChinese: convertedChinese,
      logs: logs,
      outputs: outputs,
    );
  }
}

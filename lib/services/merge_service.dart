import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/match_group.dart';
import '../models/merge_options.dart';
import '../models/subtitle_cue.dart';
import '../models/track_role.dart';
import 'bilingual_convert_service.dart';
import 'bilingual_inline.dart';
import 'blacklist.dart';
import 'extract/extract_service.dart';
import 'extract/track_info.dart';
import 'extract/track_selector.dart';
import 'file_matcher.dart';
import 'language_tag_rename_service.dart';
import 'parse/ass_writer.dart';
import 'parse/subtitle_loader.dart';
import 'text_pipeline.dart';
import 'tools/tool_resolver.dart';

class MergeProgress {
  MergeProgress({
    required this.current,
    required this.total,
    required this.message,
    this.done = false,
  });
  final int current;
  final int total;
  final String message;
  final bool done;
}

class MergeResult {
  MergeResult({
    required this.successCount,
    required this.failCount,
    required this.removedCredits,
    required this.skippedBilingual,
    required this.convertedBilingual,
    required this.logs,
    required this.outputs,
  });

  final int successCount;
  final int failCount;
  final int removedCredits;
  final List<String> skippedBilingual;
  final int convertedBilingual;
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
  });

  final MergeOptions options;
  final void Function(MergeProgress progress)? onProgress;
  final Future<bool> Function(MatchGroup group)? onConflict;
  final Future<SelectedTracks?> Function(
    String videoPath,
    List<SubtitleTrackInfo> tracks,
    ExtractNeed need,
  )? onPickTracks;
  final Set<String>? selectedPrefixes;

  bool _isSelected(MatchGroup g) {
    if (selectedPrefixes == null) return true;
    return selectedPrefixes!.contains(g.prefix);
  }

  /// Extract subtitle tracks from selected video groups only (no merge).
  Future<MergeResult> extractOnly(Directory dir) async {
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

    var groups = await FileMatcher.scanDirectory(
      dir,
      extractSubdir: options.extractSubdir,
    );
    if (selectedPrefixes != null) {
      groups = groups.where(_isSelected).toList();
    }

    final work = groups.where((g) {
      if (!_isSelected(g) || g.kind == GroupKind.bilingualFile) return false;
      if (g.video == null) return false;
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
        logs: logs,
        outputs: outputs,
      );
    }

    final extractor = ExtractService(tools, options)..onNeedUserPick = onPickTracks;
    FolderTrackChoice? folderChoice;

    for (var i = 0; i < work.length; i++) {
      final g = work[i];
      final needZh = g.chinese == null || g.chinese!.role != TrackRole.chinese;
      final needEn = g.foreign == null || g.foreign!.role != TrackRole.foreign;

      onProgress?.call(MergeProgress(
        current: i + 1,
        total: work.length,
        message: '抽取: ${g.outputBase}',
      ));

      try {
        extractor.onNeedUserPick = (path, tracks, need) async {
          if (folderChoice != null) {
            final auto = TrackSelector.autoSelect(tracks);
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
                        return TrackSelector.autoSelect(ts).chinese;
                      }
                    }
              ..pickForeign = enId == null
                  ? null
                  : (ts) {
                      try {
                        return ts.firstWhere((t) => t.id == enId);
                      } catch (_) {
                        return TrackSelector.autoSelect(ts).foreign;
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

    onProgress?.call(MergeProgress(
      current: work.length,
      total: work.length,
      message: '抽轨完成',
      done: true,
    ));

    return MergeResult(
      successCount: success,
      failCount: fail,
      removedCredits: 0,
      skippedBilingual: const [],
      convertedBilingual: 0,
      logs: logs,
      outputs: outputs,
    );
  }

  Future<MergeResult> run(Directory dir, {Directory? outputDir}) async {
    final logs = <String>[];
    final skippedBilingual = <String>[];
    final outputs = <String>[];
    var success = 0;
    var fail = 0;
    var removedCredits = 0;
    var convertedBilingual = 0;

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

    var groups = await FileMatcher.scanDirectory(
      dir,
      extractSubdir: options.extractSubdir,
    );
    if (selectedPrefixes != null) {
      groups = groups.where(_isSelected).toList();
    }
    logs.add('待处理 ${groups.length} 组');

    if (options.tagLanguageOnMerge) {
      onProgress?.call(MergeProgress(
        current: 0,
        total: groups.length,
        message: '标记语言改名…',
      ));
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
      if (g.isReady) continue;
      if (g.kind == GroupKind.bilingualFile) continue;
      if (onConflict != null) {
        final ok = await onConflict!(g);
        if (ok) FileMatcher.reevaluate(g);
      }
    }

    final blacklist = BlacklistFilter(options.blacklistRules);
    final converter = BilingualConvertService(options);
    final workList = groups.where(_isSelected).toList();

    for (var i = 0; i < workList.length; i++) {
      final g = workList[i];
      onProgress?.call(MergeProgress(
        current: i + 1,
        total: workList.length,
        message: g.kind == GroupKind.bilingualFile
            ? '转换双语: ${g.outputBase}'
            : '合并: ${g.outputBase}',
      ));

      // —— bilingual file convert ——
      if (g.kind == GroupKind.bilingualFile && g.bilingualSource != null) {
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

      if (!g.isReady) {
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
          ...zhCues.map((c) => TextPipeline.process(c, TrackRole.chinese)),
          ...enCues.map((c) => TextPipeline.process(c, TrackRole.foreign)),
        ];

        final outName = '${g.outputBase}.chs+eng.ass';
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

    onProgress?.call(MergeProgress(
      current: workList.length,
      total: workList.length,
      message: '完成',
      done: true,
    ));

    return MergeResult(
      successCount: success,
      failCount: fail,
      removedCredits: removedCredits,
      skippedBilingual: skippedBilingual.toSet().toList(),
      convertedBilingual: convertedBilingual,
      logs: logs,
      outputs: outputs,
    );
  }
}

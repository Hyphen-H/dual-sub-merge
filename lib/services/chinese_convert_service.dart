import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/merge_options.dart';
import '../models/subtitle_cue.dart';
import '../models/track_role.dart';
import 'bilingual_inline.dart';
import 'bilingual_split.dart';
import 'blacklist.dart';
import 'language_from_name.dart';
import 'parse/ass_writer.dart';
import 'parse/style_resolver.dart';
import 'parse/subtitle_document.dart';
import 'parse/subtitle_loader.dart';
import 'text_pipeline.dart';

class ChineseConvertResult {
  ChineseConvertResult({
    required this.ok,
    this.outputPath,
    this.message = '',
    this.removedCredits = 0,
    this.cueCount = 0,
  });

  final bool ok;
  final String? outputPath;
  final String message;
  final int removedCredits;
  final int cueCount;
}

/// Converts one subtitle file into a Chinese-only `.chs.ass` using HDRipad styles.
///
/// `\N` dual-line sources are split and only the Chinese half is kept; single-language
/// sources are processed as-is (inline mixed lines are never cut apart).
class ChineseConvertService {
  ChineseConvertService(this.options);

  final MergeOptions options;

  Future<ChineseConvertResult> convertFile({
    required File source,
    required Directory outDir,
    String? displayPrefix,
  }) async {
    final SubtitleDocument doc;
    try {
      doc = await SubtitleLoader.load(source);
    } catch (e) {
      return ChineseConvertResult(ok: false, message: '解析失败: $e');
    }
    if (doc.cues.isEmpty) {
      return ChineseConvertResult(ok: false, message: '无字幕行');
    }

    var cues = doc.cues;
    var removed = 0;
    if (options.removeCredits) {
      final f = BlacklistFilter(options.blacklistRules).filter(cues);
      cues = f.$1;
      removed = f.$2;
    }
    if (cues.isEmpty) {
      return ChineseConvertResult(ok: false, message: '清洗后无字幕行');
    }

    final chineseCues = <SubtitleCue>[];
    var fromDual = 0;
    var dropped = 0;

    final dual = BilingualInlineDetector.isBilingualInline(cues);
    if (dual) {
      final split = BilingualSplit.splitDocument(cues);
      if (!split.convertible) {
        return ChineseConvertResult(
          ok: false,
          message:
              '无法可靠拆分 \\N 双语 (可拆 ${split.splitOk}/${split.dualLines}, '
              '比例 ${(split.splitRatio * 100).toStringAsFixed(0)}%)',
        );
      }
      for (final item in split.items) {
        if (item.role == TrackRole.chinese) {
          chineseCues.add(item.cue);
          fromDual++;
        } else {
          dropped++;
        }
      }
    } else {
      for (final cue in cues) {
        chineseCues.add(cue);
      }
    }

    if (chineseCues.isEmpty) {
      return ChineseConvertResult(ok: false, message: '未找到中文内容');
    }

    final styles = StyleResolver.resolve(options);
    final outCues = [
      for (final cue in chineseCues)
        TextPipeline.process(
          cue,
          TrackRole.chinese,
          hdr: options.hdrSubtitle,
          names: styles.names,
          treatAn8AsAnnotation: options.an8AsAnnotation,
        ),
    ];

    final base = (displayPrefix != null && displayPrefix.isNotEmpty)
        ? displayPrefix
        : LanguageFromName.displayPrefix(source.path);
    final cleanBase = base
        .replaceAll(
          RegExp(r'\.chs\+[a-z][a-z0-9_-]*$', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\.chs$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[.\s_\-]+$'), '');
    final finalName = '$cleanBase.chs.ass';
    final outPath = p.join(outDir.path, finalName);

    if (!options.overwrite && File(outPath).existsSync()) {
      return ChineseConvertResult(ok: false, message: '已存在: $finalName');
    }

    await AssWriter.write(
      path: outPath,
      cues: outCues,
      options: options,
      title: cleanBase,
    );

    final detail = dual
        ? '取中文 $fromDual 条（丢弃外文 $dropped 条）'
        : '${outCues.length} 条';
    return ChineseConvertResult(
      ok: true,
      outputPath: outPath,
      removedCredits: removed,
      cueCount: outCues.length,
      message: '$detail → $finalName',
    );
  }
}

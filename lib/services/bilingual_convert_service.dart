import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/merge_options.dart';
import '../models/subtitle_cue.dart';
import 'bilingual_split.dart';
import 'blacklist.dart';
import 'language_from_name.dart';
import 'parse/ass_writer.dart';
import 'parse/subtitle_document.dart';
import 'parse/subtitle_loader.dart';
import 'text_pipeline.dart';

class BilingualConvertResult {
  BilingualConvertResult({
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

class BilingualConvertService {
  BilingualConvertService(this.options);

  final MergeOptions options;

  Future<BilingualConvertResult> convertFile({
    required File source,
    required Directory outDir,
    String? displayPrefix,
  }) async {
    final SubtitleDocument doc;
    try {
      doc = await SubtitleLoader.load(source);
    } catch (e) {
      return BilingualConvertResult(ok: false, message: '解析失败: $e');
    }
    if (doc.cues.isEmpty) {
      return BilingualConvertResult(ok: false, message: '无字幕行');
    }

    var cues = doc.cues;
    var removed = 0;
    if (options.removeCredits) {
      final f = BlacklistFilter(options.blacklistRules).filter(cues);
      cues = f.$1;
      removed = f.$2;
    }

    final split = BilingualSplit.splitDocument(cues);
    if (!split.convertible) {
      return BilingualConvertResult(
        ok: false,
        message:
            '无法可靠拆分 \\N 双语 (可拆 ${split.splitOk}/${split.dualLines}, 比例 ${(split.splitRatio * 100).toStringAsFixed(0)}%)',
      );
    }

    final outCues = <SubtitleCue>[
      for (final item in split.items) TextPipeline.process(item.cue, item.role),
    ];

    final base = (displayPrefix != null && displayPrefix.isNotEmpty)
        ? displayPrefix
        : LanguageFromName.displayPrefix(source.path);
    final cleanBase = base
        .replaceAll(RegExp(r'\.chs\+eng$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[.\s_\-]+$'), '');
    final finalName = '$cleanBase.chs+eng.ass';
    final outPath = p.join(outDir.path, finalName);

    if (!options.overwrite && File(outPath).existsSync()) {
      return BilingualConvertResult(ok: false, message: '已存在: $finalName');
    }

    await AssWriter.write(
      path: outPath,
      cues: outCues,
      options: options,
      title: cleanBase,
    );

    return BilingualConvertResult(
      ok: true,
      outputPath: outPath,
      removedCredits: removed,
      cueCount: outCues.length,
      message: '拆分 ${split.splitOk} 条双语 + ${split.monoKept} 条单语 → $finalName',
    );
  }
}

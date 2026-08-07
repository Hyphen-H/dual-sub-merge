import 'dart:io';

import 'package:path/path.dart' as p;

import 'ass_parser.dart';
import 'srt_parser.dart';
import 'subtitle_document.dart';
import 'text_decoder.dart';
import 'vtt_parser.dart';

enum SubtitleFormat { ass, srt, vtt }

class SubtitleLoader {
  static const exts = {'.ass', '.ssa', '.srt', '.vtt'};

  static Future<SubtitleDocument> load(File file) async {
    final text = SubtitleTextDecoder.decode(await file.readAsBytes());
    return switch (detectText(text, extension: p.extension(file.path))) {
      SubtitleFormat.ass => AssParser.parse(text, sourcePath: file.path),
      SubtitleFormat.srt => SrtParser.parse(text, sourcePath: file.path),
      SubtitleFormat.vtt => VttParser.parse(text, sourcePath: file.path),
    };
  }

  static SubtitleFormat detectText(String text, {String extension = ''}) {
    final normalized = text.replaceFirst('\uFEFF', '').trimLeft();
    final lower = normalized.toLowerCase();
    if (lower.startsWith('[script info]') ||
        (lower.contains('[events]') && lower.contains('dialogue:'))) {
      return SubtitleFormat.ass;
    }
    if (lower.startsWith('webvtt')) return SubtitleFormat.vtt;
    return switch (extension.toLowerCase()) {
      '.ass' || '.ssa' => SubtitleFormat.ass,
      '.vtt' => SubtitleFormat.vtt,
      _ => SubtitleFormat.srt,
    };
  }

  /// Repairs only old extraction outputs whose content is ASS but suffix is SRT.
  static Future<File> repairExtractedExtension(File file) async {
    if (p.extension(file.path).toLowerCase() != '.srt' ||
        !p
            .basenameWithoutExtension(file.path)
            .toLowerCase()
            .endsWith('.extracted')) {
      return file;
    }
    final text = SubtitleTextDecoder.decode(await file.readAsBytes());
    if (detectText(text, extension: '.srt') != SubtitleFormat.ass) return file;
    final target = File('${p.withoutExtension(file.path)}.ass');
    if (target.existsSync()) return file;
    try {
      return await file.rename(target.path);
    } catch (_) {
      return file;
    }
  }
}

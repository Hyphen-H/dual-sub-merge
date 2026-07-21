import 'dart:convert';
import 'dart:io';

import '../../models/subtitle_cue.dart';
import 'subtitle_document.dart';
import 'time_util.dart';

class SrtParser {
  static Future<SubtitleDocument> parseFile(File file) async {
    final bytes = await file.readAsBytes();
    return parse(_decode(bytes), sourcePath: file.path);
  }

  static SubtitleDocument parse(String content, {String sourcePath = ''}) {
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    final blocks = normalized.split(RegExp(r'\n\s*\n'));
    final cues = <SubtitleCue>[];
    final timeRe = RegExp(
      r'(\d{1,2}:\d{2}:\d{2}[,\.]\d{1,3})\s*-->\s*(\d{1,2}:\d{2}:\d{2}[,\.]\d{1,3})',
    );

    for (final block in blocks) {
      final lines = block.split('\n').where((e) => e.trim().isNotEmpty).toList();
      if (lines.isEmpty) continue;
      var idx = 0;
      if (RegExp(r'^\d+$').hasMatch(lines[0].trim())) idx = 1;
      if (idx >= lines.length) continue;
      final m = timeRe.firstMatch(lines[idx]);
      if (m == null) continue;
      final start = TimeUtil.parseSrt(m.group(1)!);
      final end = TimeUtil.parseSrt(m.group(2)!);
      final text = lines.sublist(idx + 1).join('\n');
      cues.add(SubtitleCue(startMs: start, endMs: end, rawText: text));
    }
    return SubtitleDocument(cues: cues, sourcePath: sourcePath);
  }

  static String _decode(List<int> bytes) {
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes, allowInvalid: true);
    }
  }
}

import 'dart:io';

import '../../models/subtitle_cue.dart';
import 'subtitle_document.dart';
import 'text_decoder.dart';
import 'time_util.dart';

class VttParser {
  static Future<SubtitleDocument> parseFile(File file) async {
    final bytes = await file.readAsBytes();
    return parse(SubtitleTextDecoder.decode(bytes), sourcePath: file.path);
  }

  static SubtitleDocument parse(String content, {String sourcePath = ''}) {
    var text = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (text.startsWith('WEBVTT')) {
      final firstNl = text.indexOf('\n');
      text = firstNl >= 0 ? text.substring(firstNl + 1) : '';
    }
    final blocks = text.trim().split(RegExp(r'\n\s*\n'));
    final cues = <SubtitleCue>[];
    final timeRe = RegExp(
      r'((?:\d{1,2}:)?\d{1,2}:\d{2}\.\d{1,3})\s*-->\s*((?:\d{1,2}:)?\d{1,2}:\d{2}\.\d{1,3})',
    );

    for (final block in blocks) {
      final lines = block
          .split('\n')
          .where((e) => e.trim().isNotEmpty)
          .toList();
      if (lines.isEmpty) continue;
      var idx = 0;
      if (!timeRe.hasMatch(lines[0]) && lines.length > 1) idx = 1;
      if (idx >= lines.length) continue;
      final m = timeRe.firstMatch(lines[idx]);
      if (m == null) continue;
      final start = _parseVtt(m.group(1)!);
      final end = _parseVtt(m.group(2)!);
      final body = lines.sublist(idx + 1).join('\n');
      cues.add(SubtitleCue(startMs: start, endMs: end, rawText: body));
    }
    return SubtitleDocument(cues: cues, sourcePath: sourcePath);
  }

  static int _parseVtt(String s) {
    final parts = s.trim().split(':');
    if (parts.length == 2) {
      return TimeUtil.parseSrt(
        '00:${parts[0]}:${parts[1].replaceAll('.', ',')}',
      );
    }
    return TimeUtil.parseSrt(s.replaceAll('.', ','));
  }
}

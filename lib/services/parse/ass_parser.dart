import 'dart:io';

import '../../models/ass_style.dart';
import '../../models/subtitle_cue.dart';
import 'subtitle_document.dart';
import 'text_decoder.dart';
import 'time_util.dart';

class AssParser {
  static Future<SubtitleDocument> parseFile(File file) async {
    final bytes = await file.readAsBytes();
    final text = SubtitleTextDecoder.decode(bytes);
    return parse(text, sourcePath: file.path);
  }

  static SubtitleDocument parse(String content, {String sourcePath = ''}) {
    final lines = content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    final styles = <AssStyle>[];
    final cues = <SubtitleCue>[];
    int? playResX;
    int? playResY;
    var section = '';

    for (final raw in lines) {
      final line = raw.trimRight();
      final t = line.trim();
      if (t.isEmpty) continue;
      if (t.startsWith('[') && t.endsWith(']')) {
        section = t.toLowerCase();
        continue;
      }
      if (section.contains('script info')) {
        final lower = t.toLowerCase();
        if (lower.startsWith('playresx:')) {
          playResX = int.tryParse(t.split(':').last.trim());
        } else if (lower.startsWith('playresy:')) {
          playResY = int.tryParse(t.split(':').last.trim());
        }
        continue;
      }
      if (section.contains('v4') && section.contains('styles')) {
        final style = AssStyle.tryParse(t);
        if (style != null) styles.add(style);
        continue;
      }
      if (section.contains('events')) {
        if (t.toLowerCase().startsWith('format:')) continue;
        if (!t.toLowerCase().startsWith('dialogue:')) continue;
        final body = t.substring(t.indexOf(':') + 1).trim();
        final parts = _splitDialogue(body, 9);
        if (parts.length < 10) continue;
        final layer = int.tryParse(parts[0].trim()) ?? 0;
        final start = TimeUtil.parseAss(parts[1].trim());
        final end = TimeUtil.parseAss(parts[2].trim());
        final styleName = parts[3].trim();
        final name = parts[4].trim();
        final ml = int.tryParse(parts[5].trim()) ?? 0;
        final mr = int.tryParse(parts[6].trim()) ?? 0;
        final mv = int.tryParse(parts[7].trim()) ?? 0;
        final effect = parts[8].trim();
        final text = parts.sublist(9).join(',');
        cues.add(
          SubtitleCue(
            startMs: start,
            endMs: end,
            rawText: text,
            layer: layer,
            styleName: styleName,
            name: name,
            effect: effect,
            marginL: ml,
            marginR: mr,
            marginV: mv,
          ),
        );
      }
    }
    return SubtitleDocument(
      cues: cues,
      styles: styles,
      playResX: playResX,
      playResY: playResY,
      sourcePath: sourcePath,
    );
  }

  static List<String> _splitDialogue(String body, int maxSplits) {
    final out = <String>[];
    var current = StringBuffer();
    var splits = 0;
    for (var i = 0; i < body.length; i++) {
      final ch = body[i];
      if (ch == ',' && splits < maxSplits) {
        out.add(current.toString());
        current = StringBuffer();
        splits++;
      } else {
        current.write(ch);
      }
    }
    out.add(current.toString());
    return out;
  }
}

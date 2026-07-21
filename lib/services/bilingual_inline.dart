import '../models/subtitle_cue.dart';
import 'text_pipeline.dart';

class BilingualInlineDetector {
  /// Returns true if document looks like line-internal CN+EN dual subtitles
  /// (multi-line with \\N, or single-line mixed CN+EN).
  static bool isBilingualInline(List<SubtitleCue> cues, {double threshold = 0.35}) {
    if (cues.isEmpty) return false;
    var sample = cues.length;
    if (sample > 80) sample = 80;
    var hits = 0;
    var checked = 0;

    for (var i = 0; i < sample; i++) {
      final raw = cues[i].rawText;
      checked++;
      if (_looksDualLine(raw)) hits++;
    }

    if (checked == 0) return false;
    // strong signal: enough dual lines
    if (hits >= 5 && hits / checked >= threshold) return true;
    if (hits >= 3 && hits / checked >= 0.8) return true;
    return false;
  }

  static bool _looksDualLine(String raw) {
    if (_hasHardBreak(raw)) {
      return _looksDualSplit(raw) || _looksSingleLineMixed(raw);
    }
    return _looksSingleLineMixed(raw);
  }

  static bool _hasHardBreak(String raw) {
    return raw.contains(r'\N') || raw.contains('\n');
  }

  static bool _looksDualSplit(String raw) {
    final parts = raw.split(RegExp(r'\\N|\n'));
    if (parts.length < 2) return false;
    final segs = parts.map(TextPipeline.plainText).where((e) => e.isNotEmpty).toList();
    if (segs.length < 2) return false;
    final a = segs.first;
    final b = segs[1];
    final aHan = RegExp(r'[\u4e00-\u9fff]').hasMatch(a);
    final bHan = RegExp(r'[\u4e00-\u9fff]').hasMatch(b);
    final aLat = RegExp(r'[A-Za-z]{2,}').hasMatch(a);
    final bLat = RegExp(r'[A-Za-z]{2,}').hasMatch(b);
    final dual = (aHan && bLat && !bHan) ||
        (bHan && aLat && !aHan) ||
        (aHan && bLat) ||
        (bHan && aLat);
    final dualFn = RegExp(r'\\fn', caseSensitive: false).allMatches(raw).length >= 2;
    return dual || (dualFn && (aHan || bHan) && (aLat || bLat));
  }

  /// Single dialogue line containing both Chinese and foreign text.
  static bool _looksSingleLineMixed(String raw) {
    final plain = TextPipeline.plainText(raw);
    if (plain.isEmpty) return false;

    final han = RegExp(r'[\u4e00-\u9fff]').allMatches(plain).length;
    final latinWords = RegExp(r'[A-Za-z]{2,}').allMatches(plain).length;
    final dualFn = RegExp(r'\\fn', caseSensitive: false).allMatches(raw).length >= 2;

    // dual font overrides often used for single-line dual
    if (dualFn && han >= 2 && latinWords >= 2) return true;

    // substantial both sides on one line (not just one English name in Chinese)
    if (han >= 4 && latinWords >= 3) return true;
    if (han >= 2 && latinWords >= 5) return true;

    return false;
  }
}

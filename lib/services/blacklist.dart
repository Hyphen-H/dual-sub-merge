import '../models/subtitle_cue.dart';
import 'text_pipeline.dart';

class BlacklistFilter {
  BlacklistFilter(List<String> rules) {
    final compiled = _compilePair(rules);
    _regexes = compiled.$1;
    invalidRules = compiled.$2;
  }

  late final List<RegExp> _regexes;
  late final List<String> invalidRules;

  static (List<RegExp>, List<String>) _compilePair(List<String> rules) {
    final regs = <RegExp>[];
    final invalid = <String>[];
    for (final raw in rules) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final pattern = line.replaceAll(r'$中文字符', r'[\u4e00-\u9fff]+');
      try {
        regs.add(RegExp(pattern, caseSensitive: false, unicode: true));
      } catch (_) {
        invalid.add(line);
      }
    }
    return (regs, invalid);
  }

  static List<String> validateRules(List<String> rules) => _compilePair(rules).$2;

  (List<SubtitleCue>, int) filter(List<SubtitleCue> cues) {
    if (_regexes.isEmpty) return (cues, 0);
    final kept = <SubtitleCue>[];
    var removed = 0;
    for (final cue in cues) {
      final plain = TextPipeline.plainText(cue.rawText);
      if (_regexes.any((r) => r.hasMatch(plain))) {
        removed++;
      } else {
        kept.add(cue);
      }
    }
    return (kept, removed);
  }
}

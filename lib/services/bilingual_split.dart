import '../models/subtitle_cue.dart';
import '../models/track_role.dart';
import 'language_from_name.dart';
import 'text_pipeline.dart';

class SplitPair {
  const SplitPair({required this.chinese, required this.foreign});
  final String chinese;
  final String foreign;
}

class BilingualSplit {
  /// Try split one cue text by \\N / newline into CN + foreign raw segments.
  /// Returns null if not a clean dual pair.
  static SplitPair? trySplitRaw(String raw) {
    if (!_hasHardBreak(raw)) return null;
    final parts = raw.split(RegExp(r'\\N|\n'));
    final segs = <String>[];
    for (final p in parts) {
      final t = p.trim();
      if (t.isEmpty) continue;
      // drop empty-after-plain segments
      if (TextPipeline.plainText(t).isEmpty) continue;
      segs.add(t);
    }
    if (segs.length < 2) return null;

    // Prefer first two meaningful segments (classic dual layout)
    final a = segs[0];
    final b = segs[1];
    final roleA = LanguageFromName.scoreLine(TextPipeline.plainText(a));
    final roleB = LanguageFromName.scoreLine(TextPipeline.plainText(b));

    if (roleA == TrackRole.chinese && roleB == TrackRole.foreign) {
      return SplitPair(chinese: a, foreign: b);
    }
    if (roleA == TrackRole.foreign && roleB == TrackRole.chinese) {
      return SplitPair(chinese: b, foreign: a);
    }

    // Heuristic fallback: more Han → chinese
    final hanA = RegExp(r'[\u4e00-\u9fff]').allMatches(TextPipeline.plainText(a)).length;
    final hanB = RegExp(r'[\u4e00-\u9fff]').allMatches(TextPipeline.plainText(b)).length;
    final latA = RegExp(r'[A-Za-z]{2,}').allMatches(TextPipeline.plainText(a)).length;
    final latB = RegExp(r'[A-Za-z]{2,}').allMatches(TextPipeline.plainText(b)).length;
    if (hanA > 0 && latB > 0 && hanA >= hanB && latB >= latA) {
      return SplitPair(chinese: a, foreign: b);
    }
    if (hanB > 0 && latA > 0 && hanB >= hanA && latA >= latB) {
      return SplitPair(chinese: b, foreign: a);
    }
    return null;
  }

  /// Whether this cue looks like \\N dual that we can split.
  static bool canSplit(SubtitleCue cue) => trySplitRaw(cue.rawText) != null;

  /// Expand cues: dual lines → 2 cues (same timing); mono kept as single with role.
  /// Returns (outCues already role-tagged via temp style field unused — use SplitResult).
  static BilingualSplitResult splitDocument(List<SubtitleCue> cues, {double minSplitRatio = 0.7}) {
    final out = <({SubtitleCue cue, TrackRole role})>[];
    var dualHits = 0;
    var dualOk = 0;
    var mono = 0;
    var dropped = 0;

    for (final cue in cues) {
      if (_hasHardBreak(cue.rawText)) {
        dualHits++;
        final pair = trySplitRaw(cue.rawText);
        if (pair != null) {
          dualOk++;
          out.add((
            cue: cue.copyWith(rawText: pair.foreign, text: pair.foreign),
            role: TrackRole.foreign,
          ));
          out.add((
            cue: cue.copyWith(rawText: pair.chinese, text: pair.chinese),
            role: TrackRole.chinese,
          ));
          continue;
        }
        // hard break but not dual — try treat whole as one language
        final role = LanguageFromName.scoreLine(TextPipeline.plainText(cue.rawText));
        if (role == TrackRole.chinese || role == TrackRole.foreign) {
          mono++;
          out.add((cue: cue, role: role));
        } else {
          dropped++;
        }
        continue;
      }

      final role = LanguageFromName.scoreLine(TextPipeline.plainText(cue.rawText));
      if (role == TrackRole.chinese || role == TrackRole.foreign) {
        mono++;
        out.add((cue: cue, role: role));
      } else if (TextPipeline.plainText(cue.rawText).isEmpty) {
        dropped++;
      } else {
        // weak mono — keep as chinese if any Han else foreign
        final plain = TextPipeline.plainText(cue.rawText);
        final hasHan = RegExp(r'[\u4e00-\u9fff]').hasMatch(plain);
        mono++;
        out.add((cue: cue, role: hasHan ? TrackRole.chinese : TrackRole.foreign));
      }
    }

    final ratio = dualHits == 0 ? 0.0 : dualOk / dualHits;
    final convertible = dualHits > 0 && ratio >= minSplitRatio && dualOk >= 3;
    // small files: allow if almost all dual lines split
    final smallOk = dualHits > 0 && dualHits < 5 && dualOk == dualHits && dualOk >= 1;

    return BilingualSplitResult(
      items: out,
      dualLines: dualHits,
      splitOk: dualOk,
      monoKept: mono,
      dropped: dropped,
      convertible: convertible || smallOk,
      splitRatio: ratio,
    );
  }

  static bool _hasHardBreak(String raw) => raw.contains(r'\N') || raw.contains('\n');
}

class BilingualSplitResult {
  BilingualSplitResult({
    required this.items,
    required this.dualLines,
    required this.splitOk,
    required this.monoKept,
    required this.dropped,
    required this.convertible,
    required this.splitRatio,
  });

  final List<({SubtitleCue cue, TrackRole role})> items;
  final int dualLines;
  final int splitOk;
  final int monoKept;
  final int dropped;
  final bool convertible;
  final double splitRatio;
}

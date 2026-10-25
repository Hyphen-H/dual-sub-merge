import 'package:path/path.dart' as p;

import '../models/track_role.dart';
import 'text_pipeline.dart';

class LanguageFromName {
  static final _chineseTokens = <String>{
    'chs',
    'cht',
    'zh',
    'cn',
    'chi',
    'zho',
    'gb',
    'big5',
    'sc',
    'tc',
    '简体',
    '繁体',
    '繁中',
    '简中',
    '中字',
    '中文',
  };

  static final _foreignTokens = <String>{
    'eng',
    'en',
    'en-us',
    'en-gb',
    'english',
    'jpn',
    'ja',
    'jp',
    'jap',
    'japanese',
    'kor',
    'ko',
    'korean',
    'fre',
    'fr',
    'fra',
    'french',
    'ger',
    'de',
    'deu',
    'german',
    'spa',
    'es',
    'spanish',
    'rus',
    'ru',
    'ita',
    'it',
    'por',
    'pt',
    'vie',
    'vi',
    'tha',
    'th',
    'ara',
    'ar',
    '外挂',
    '英文',
    'sdh',
    'cc',
  };

  static TrackRole fromPath(String path) {
    final base = p.basenameWithoutExtension(path).toLowerCase();
    final hasChineseMarker = base.contains('chi') || base.contains('chs');
    final hasEnglishMarker = base.contains('eng');
    if (hasChineseMarker && !hasEnglishMarker) return TrackRole.chinese;
    if (hasEnglishMarker && !hasChineseMarker) return TrackRole.foreign;
    if (hasChineseMarker && hasEnglishMarker) return TrackRole.unknown;

    // split on common separators
    final tokens = base
        .split(RegExp(r'[.\s_\-\[\]()]+'))
        .where((t) => t.isNotEmpty)
        .toList();

    // prefer trailing tokens (filename markers usually at end)
    for (var i = tokens.length - 1; i >= 0; i--) {
      final t = tokens[i];
      if (_chineseTokens.contains(t)) return TrackRole.chinese;
      if (_foreignTokens.contains(t)) return TrackRole.foreign;
      // chs&eng style combined -> unknown for whole file
      if (t.contains('chs') && (t.contains('eng') || t.contains('en'))) {
        return TrackRole.unknown;
      }
    }

    // also check full lower name contains .chs. etc
    final lower = base;
    if (RegExp(
      r'(^|[.\s_\-])(chs|cht|zh|cn|chi)([.\s_\-]|$)',
    ).hasMatch(lower)) {
      return TrackRole.chinese;
    }
    if (RegExp(
      r'(^|[.\s_\-])(eng|en|sdh|jpn|ja|jp|kor|ko)([.\s_\-]|$)',
    ).hasMatch(lower)) {
      return TrackRole.foreign;
    }
    return TrackRole.unknown;
  }

  /// True when basename ends with a known language token (requires separator,
  /// so words like "episode" are not treated as tagged via trailing "de").
  static bool hasTrailingLanguageTag(String path) {
    final base = p.basenameWithoutExtension(path);
    return RegExp(
      r'(?:^|[.\s_\-\[\]()])(?:'
      r'chs|cht|zh|cn|chi|zho|gb|big5|sc|tc|'
      r'eng|en|en-us|en-gb|english|'
      r'jpn|ja|jp|jap|kor|ko|'
      r'fre|fr|fra|ger|de|deu|spa|es|rus|ru|ita|it|por|pt|vie|vi|tha|th|ara|ar|'
      r'sdh|cc|extracted|'
      r'简体|繁体|繁中|简中|中字|中文|英文|外挂'
      r')$',
      caseSensitive: false,
    ).hasMatch(base);
  }

  static final _kana = RegExp(r'[\u3040-\u309F\u30A0-\u30FF]');

  static int kanaCount(String s) => _kana.allMatches(s).length;

  /// Content majority vote fallback.
  static TrackRole fromContent(Iterable<String> rawTexts, {int sample = 40}) {
    var han = 0;
    var latin = 0;
    var kana = 0;
    var n = 0;
    for (final raw in rawTexts) {
      if (n >= sample) break;
      final plain = TextPipeline.plainText(raw);
      if (plain.isEmpty) continue;
      n++;
      han += RegExp(r'[\u4e00-\u9fff]').allMatches(plain).length;
      latin += RegExp(r'[A-Za-z]').allMatches(plain).length;
      kana += kanaCount(plain);
    }
    // Kana marks Japanese: Japanese dialogue always carries kana/okurigana,
    // while Chinese text essentially never contains kana.
    if (kana >= 5) return TrackRole.foreign;
    if (han == 0 && latin == 0) return TrackRole.unknown;
    if (han > latin) return TrackRole.chinese;
    if (latin > han) return TrackRole.foreign;
    return TrackRole.foreign;
  }

  static TrackRole scoreLine(String plain) {
    // A couple of kana already means Japanese, even with mixed-in kanji.
    if (kanaCount(plain) >= 2) return TrackRole.foreign;
    final han = RegExp(r'[\u4e00-\u9fff]').allMatches(plain).length;
    final latin = RegExp(r'[A-Za-z]').allMatches(plain).length;
    final total = plain.replaceAll(RegExp(r'\s'), '').length;
    if (total == 0) return TrackRole.unknown;
    if (han >= 2 || (han > 0 && han / total >= 0.2)) return TrackRole.chinese;
    if (latin >= 2 && han == 0) return TrackRole.foreign;
    if (latin > han * 3) return TrackRole.foreign;
    if (han > 0) return TrackRole.chinese;
    return TrackRole.unknown;
  }

  static const _langTagAliases = <String, String>{
    'chs': 'chs',
    'cht': 'cht',
    'zh': 'chs',
    'cn': 'chs',
    'chi': 'chs',
    'zho': 'chs',
    'sc': 'chs',
    'tc': 'cht',
    'jpn': 'jpn',
    'ja': 'jpn',
    'jp': 'jpn',
    'jap': 'jpn',
    'japanese': 'jpn',
    'eng': 'eng',
    'en': 'eng',
    'en-us': 'eng',
    'en-gb': 'eng',
    'english': 'eng',
    'sdh': 'eng',
    'cc': 'eng',
    'kor': 'kor',
    'ko': 'kor',
    'korean': 'kor',
    'fre': 'fre',
    'fr': 'fre',
    'fra': 'fre',
    'french': 'fre',
    'ger': 'ger',
    'de': 'ger',
    'deu': 'ger',
    'german': 'ger',
    'spa': 'spa',
    'es': 'spa',
    'spanish': 'spa',
    'rus': 'rus',
    'ru': 'rus',
    'ita': 'ita',
    'it': 'ita',
    'por': 'por',
    'pt': 'por',
    'vie': 'vie',
    'vi': 'vie',
    'tha': 'tha',
    'th': 'tha',
    'ara': 'ara',
    'ar': 'ara',
  };

  /// ISO-ish language tag for output naming, scanned from trailing filename
  /// tokens. Returns null when nothing is recognised.
  static String? explicitOutputFileTag(String path) {
    final base = p.basenameWithoutExtension(path).toLowerCase();
    final tokens = base
        .split(RegExp(r'[.\s_\-\[\]()]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    for (var i = tokens.length - 1; i >= 0; i--) {
      final tag = _langTagAliases[tokens[i]];
      if (tag != null) return tag;
    }
    return null;
  }

  /// Same as [explicitOutputFileTag] but falls back to [fallback] (default
  /// `eng`) when no filename token is recognised.
  static String outputFileTag(String path, {String fallback = 'eng'}) {
    return explicitOutputFileTag(path) ?? fallback;
  }

  /// Container track language → output tag. Unknown/und falls back to
  /// [fallback] (default `eng`) so prefix pairing keeps working.
  static String foreignOutputTag(String? language, {String fallback = 'eng'}) {
    final key = (language ?? '').trim().toLowerCase().replaceAll('_', '-');
    if (key.isEmpty || key == 'und') return fallback;
    return _langTagAliases[key] ?? fallback;
  }

  /// Content-based language tag: `jpn` when kana is present, else null.
  static String? tagFromContent(Iterable<String> rawTexts, {int sample = 40}) {
    var kana = 0;
    var n = 0;
    for (final raw in rawTexts) {
      if (n >= sample) break;
      final plain = TextPipeline.plainText(raw);
      if (plain.isEmpty) continue;
      n++;
      kana += kanaCount(plain);
    }
    if (kana >= 5) return 'jpn';
    return null;
  }

  /// True when the filename carries an explicit Japanese tag.
  static bool isJapanesePath(String path) =>
      explicitOutputFileTag(path) == 'jpn';

  /// Strip language tokens for prefix matching (case-insensitive key).
  static String normalizePrefix(String path) {
    return displayPrefix(path).toLowerCase();
  }

  /// Same as normalize but keeps original casing for output filenames.
  static String displayPrefix(String path) {
    var base = p.basenameWithoutExtension(path);
    final tokenRe = RegExp(
      // Extracted tracks may be named like `...t4.[eng]` / `...t8.[chi]`.
      // Consume the optional track number together with the language suffix
      // so both files normalize to the same pairing prefix.
      r'[.\s_\-]*(?:t\d+[.\s_\-]*)?[\[\(]?(chs|cht|zh|cn|chi|zho|gb|big5|sc|tc|eng|en|en-us|en-gb|english|jpn|ja|jp|jap|kor|ko|fre|fr|fra|ger|de|deu|spa|es|rus|ru|ita|it|por|pt|vie|vi|tha|th|ara|ar|sdh|cc|extracted|简体|繁体|繁中|简中|中字|中文|英文|外挂)+[\]\)]?$',
      caseSensitive: false,
    );
    var prev = '';
    while (base != prev) {
      prev = base;
      base = base.replaceAll(tokenRe, '');
    }
    return base.replaceAll(RegExp(r'[.\s_\-]+$'), '');
  }
}

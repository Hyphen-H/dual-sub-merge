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
    if (RegExp(r'(^|[.\s_\-])(chs|cht|zh|cn|chi)([.\s_\-]|$)').hasMatch(lower)) {
      return TrackRole.chinese;
    }
    if (RegExp(r'(^|[.\s_\-])(eng|en|sdh|jpn|jp|kor|ko)([.\s_\-]|$)').hasMatch(lower)) {
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
      r'jpn|jp|jap|kor|ko|'
      r'fre|fr|fra|ger|de|deu|spa|es|rus|ru|ita|it|por|pt|vie|vi|tha|th|ara|ar|'
      r'sdh|cc|extracted|'
      r'简体|繁体|繁中|简中|中字|中文|英文|外挂'
      r')$',
      caseSensitive: false,
    ).hasMatch(base);
  }

  /// Content majority vote fallback.
  static TrackRole fromContent(Iterable<String> rawTexts, {int sample = 40}) {
    var zh = 0;
    var foreign = 0;
    var n = 0;
    for (final raw in rawTexts) {
      if (n >= sample) break;
      final plain = TextPipeline.plainText(raw);
      if (plain.isEmpty) continue;
      n++;
      final role = scoreLine(plain);
      if (role == TrackRole.chinese) {
        zh++;
      } else if (role == TrackRole.foreign) {
        foreign++;
      }
    }
    if (zh == 0 && foreign == 0) return TrackRole.unknown;
    if (zh >= foreign) return TrackRole.chinese;
    return TrackRole.foreign;
  }

  static TrackRole scoreLine(String plain) {
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

  /// Strip language tokens for prefix matching (case-insensitive key).
  static String normalizePrefix(String path) {
    return displayPrefix(path).toLowerCase();
  }

  /// Same as normalize but keeps original casing for output filenames.
  static String displayPrefix(String path) {
    var base = p.basenameWithoutExtension(path);
    final tokenRe = RegExp(
      r'[.\s_\-]*(chs|cht|zh|cn|chi|zho|gb|big5|sc|tc|eng|en|en-us|en-gb|english|jpn|jp|jap|kor|ko|fre|fr|ger|de|spa|es|rus|ru|sdh|cc|extracted|简体|繁体|繁中|简中|中字|中文|英文|外挂)+$',
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

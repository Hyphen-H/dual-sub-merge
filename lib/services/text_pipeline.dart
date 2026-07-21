import '../models/ass_style.dart';
import '../models/subtitle_cue.dart';
import '../models/track_role.dart';

class TextPipeline {
  static final _overrideBlock = RegExp(r'\{[^}]*\}');
  static final _an8 = RegExp(r'\\an8\b', caseSensitive: false);
  static final _keepItalic = RegExp(r'\\i[01]?(?![a-zA-Z0-9])');
  static final _music = RegExp(r'[♪♫🎵🎶]');
  static final _starWrap = RegExp(r'^\s*\*(.+)\*\s*$');
  static final _cjkComma = RegExp(r'([\u4e00-\u9fff]),([\u4e00-\u9fff])');
  static final _latinComma = RegExp(r'([A-Za-z]),([A-Za-z])');

  static const _fullToHalf = {
    '，': ',',
    '。': '.',
    '！': '!',
    '？': '?',
    '：': ':',
    '；': ';',
    '（': '(',
    '）': ')',
    '【': '[',
    '】': ']',
    '「': '"',
    '」': '"',
    '『': '"',
    '』': '"',
    '、': ',',
    '～': '~',
    '—': '-',
    '…': '...',
    '　': ' ',
    '“': '"',
    '”': '"',
    '‘': "'",
    '’': "'",
  };

  static final _htmlItalicOpen = RegExp(r'<\s*i(?:\s[^>]*)?>', caseSensitive: false);
  static final _htmlItalicClose = RegExp(r'<\s*/\s*i\s*>', caseSensitive: false);
  static final _htmlEmOpen = RegExp(r'<\s*em(?:\s[^>]*)?>', caseSensitive: false);
  static final _htmlEmClose = RegExp(r'<\s*/\s*em\s*>', caseSensitive: false);
  static final _htmlOther = RegExp(r'</?[a-zA-Z][^>]*>');

  /// Strip tags but keep plain text (for blacklist / language / lyric checks).
  static String plainText(String raw) {
    return raw
        .replaceAll(_overrideBlock, '')
        .replaceAll(_htmlOther, '')
        .replaceAll(r'\N', ' ')
        .replaceAll(r'\n', ' ')
        .replaceAll(r'\h', ' ')
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static SubtitleCue process(SubtitleCue cue, TrackRole role) {
    final raw = cue.rawText;
    final hadAn8 = _an8.hasMatch(raw);
    final plain = plainText(raw);
    final isLyric = _isLyric(plain);
    final cleaned = _cleanKeepItalic(_htmlItalicToAss(raw));
    final normalized = _normalizePunct(cleaned);
    final style = resolveStyle(
      role: role,
      isLyric: isLyric,
      isAnnotation: hadAn8,
    );

    return cue.copyWith(
      sourceHadAn8: hadAn8,
      isLyric: isLyric,
      isAnnotation: hadAn8,
      text: normalized,
      outputStyle: style,
    );
  }

  static String resolveStyle({
    required TrackRole role,
    required bool isLyric,
    required bool isAnnotation,
  }) {
    if (isLyric) return StyleCatalog.lyric;
    if (isAnnotation) return StyleCatalog.annotation;
    if (role == TrackRole.foreign) return StyleCatalog.foreign;
    return StyleCatalog.chinese;
  }

  static bool _isLyric(String plain) {
    if (plain.isEmpty) return false;
    if (_music.hasMatch(plain)) return true;
    final m = _starWrap.firstMatch(plain);
    return m != null && m.group(1)!.trim().isNotEmpty;
  }

  /// SRT/VTT HTML italics → Aegisub ASS: {\i1}...{\i0}
  static String _htmlItalicToAss(String raw) {
    return raw
        .replaceAll(_htmlItalicOpen, r'{\i1}')
        .replaceAll(_htmlItalicClose, r'{\i0}')
        .replaceAll(_htmlEmOpen, r'{\i1}')
        .replaceAll(_htmlEmClose, r'{\i0}');
  }

  static String _cleanKeepItalic(String raw) {
    final withNewlines = raw
        .replaceAll(r'\N', ' ')
        .replaceAll(r'\n', ' ')
        .replaceAll(r'\h', ' ')
        .replaceAll('\r\n', ' ')
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ');

    // Keep only italic overrides inside {...}; drop other ASS tags.
    var cleaned = withNewlines.replaceAllMapped(_overrideBlock, (m) {
      final inner = m.group(0)!;
      final kept = _keepItalic.allMatches(inner).map((e) => e.group(0)!).toList();
      if (kept.isEmpty) return '';
      return '{${kept.join()}}';
    });

    // Drop remaining non-italic HTML tags (b, u, font, etc.)
    cleaned = cleaned.replaceAll(_htmlOther, '');

    return cleaned.replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();
  }

  static String _normalizePunct(String input) {
    final buf = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      buf.write(_fullToHalf[ch] ?? ch);
    }
    var s = buf.toString();
    // curly leftovers already mapped; fix paired smart quotes if any remain
    s = s.replaceAll('＂', '"').replaceAll('＇', "'");
    // Chinese + comma + Chinese => add space after comma
    while (_cjkComma.hasMatch(s)) {
      s = s.replaceAllMapped(_cjkComma, (m) => '${m.group(1)}, ${m.group(2)}');
    }
    // English + comma + English => add space after comma (skip digits like 1,000)
    while (_latinComma.hasMatch(s)) {
      s = s.replaceAllMapped(_latinComma, (m) => '${m.group(1)}, ${m.group(2)}');
    }
    return s.replaceAll(RegExp(r' +'), ' ').trim();
  }
}

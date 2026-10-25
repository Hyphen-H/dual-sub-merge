import 'process_mode.dart';

class AssStyle {
  const AssStyle({required this.name, required this.line});

  final String name;
  final String line;

  static AssStyle? tryParse(String raw) {
    final line = raw.trim();
    if (!line.toLowerCase().startsWith('style:')) return null;
    final body = line.substring(6).trim();
    final name = body.split(',').first.trim();
    if (name.isEmpty) return null;
    return AssStyle(
      name: name,
      line: line.startsWith('Style:') ? line : 'Style: $body',
    );
  }
}

/// The four output roles we always emit a style for.
enum StyleRole { chinese, foreign, annotation, lyric }

/// Style names a Dialogue line references, resolved from the style table that
/// will actually be written (the built-in table or the Dial-based JP preset).
class StyleNames {
  const StyleNames({
    required this.chinese,
    required this.foreign,
    required this.annotation,
    required this.lyric,
  });

  final String chinese;
  final String foreign;
  final String annotation;
  final String lyric;
}

class StyleCatalog {
  static const chinese = '中下HDRipad';
  static const foreign = '英上HDRipad';
  static const annotation = 'annotationHDRipad';
  static const lyric = 'LyricHDRipad';

  /// 中日参考样式名（Dial 命名，不含顶部 *2 变体）。
  static const dialChinese = 'Dial-CH';
  static const dialForeign = 'Dial-JP';

  /// SDR body colour: pure white.
  static const sdrPrimaryColour = '&H00FFFFFF';

  /// dimmed HDR white: `&H4DFFFFFF` = white at 77/255 alpha.
  static const hdrPrimaryColour = '&H4DFFFFFF';

  static const defaultStyleLines = [
    'Style: 中下HDRipad,FZHei-B01,70,&H4DFFFFFF,&H4DFFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,1,2,5,5,-55,134',
    'Style: 英上HDRipad,Microsoft YaHei,80,&H4DFFFFFF,&H4DFFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,1,2,5,5,35,134',
    'Style: annotationHDRipad,FZHei-B01,60,&H4DFFFFFF,&H4DFFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,1,8,0,0,60,1',
    'Style: LyricHDRipad,Microsoft YaHei,60,&H4DFFFFFF,&H4DFFFFFF,&H00000000,&H00000000,0,-1,0,0,100,100,0,0,1,2,1,8,0,0,60,1',
  ];

  /// Pre-dimmed-HDR built-ins, kept only to migrate old persisted settings.
  static const legacyDefaultStyleLines = [
    'Style: 中下HDRipad,FZHei-B01,70,&H00828282,&H00B4B4B4,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,1,2,5,5,-55,134',
    'Style: 英上HDRipad,Microsoft YaHei,80,&H00828282,&H00B4B4B4,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,1,2,5,5,35,134',
    'Style: annotationHDRipad,FZHei-B01,60,&H00828282,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,1,8,0,0,60,1',
    'Style: LyricHDRipad,Microsoft YaHei,60,&H00828282,&H00C8C8C8,&H00000000,&H00000000,0,-1,0,0,100,100,0,0,1,2,1,8,0,0,60,1',
  ];

  /// Authored resolution of [defaultStyleLines].
  static const defaultBaseResY = 1080;

  /// 中日参考预设：取自《赛博朋克：边缘行者》JPSC BDRip 的
  /// Dial-CH / Dial-JP（不含顶部 *2 变体）。中文 48 号在上（MarginV 40），
  /// 日文 32 号贴底（MarginV 10），字号比 1.5:1。基准分辨率为 720p。
  static const jpReferenceBaseResY = 720;

  static const jpReferenceStyleLines = [
    'Style: Dial-CH,HYQiHei-65S,48,&H4DFFFFFF,&H4DFFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,0,2,10,10,40,1',
    'Style: Dial-JP,FOT-Rodin ProN B,32,&H4DFFFFFF,&H4DFFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,1.6,0,2,10,10,10,1',
    'Style: annotationHDRipad,HYQiHei-65S,40,&H4DFFFFFF,&H4DFFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,1,0,8,10,10,40,134',
    'Style: LyricHDRipad,FOT-Rodin ProN B,40,&H4DFFFFFF,&H4DFFFFFF,&H00000000,&H00000000,0,-1,0,0,100,100,0,0,1,1,0,8,10,10,40,1',
  ];

  /// Earlier JP preset that still used the generic role names.
  static const legacyJpReferenceStyleLines = [
    'Style: 中下HDRipad,HYQiHei-65S,48,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,0,2,10,10,40,134',
    'Style: 英上HDRipad,FOT-Rodin ProN B,32,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,1.6,0,2,10,10,10,1',
    'Style: annotationHDRipad,HYQiHei-65S,40,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,1,0,8,10,10,40,134',
    'Style: LyricHDRipad,FOT-Rodin ProN B,40,&H00FFFFFF,&H00C8C8C8,&H00000000,&H00000000,0,-1,0,0,100,100,0,0,1,1,0,8,10,10,40,1',
  ];

  static List<AssStyle> defaults() =>
      defaultStyleLines.map((e) => AssStyle.tryParse(e)!).toList();

  static String name(StyleRole role) => switch (role) {
    StyleRole.chinese => chinese,
    StyleRole.foreign => foreign,
    StyleRole.annotation => annotation,
    StyleRole.lyric => lyric,
  };

  static const _aliases = <StyleRole, List<String>>{
    StyleRole.chinese: [chinese, dialChinese],
    StyleRole.foreign: [foreign, dialForeign],
    StyleRole.annotation: [annotation],
    StyleRole.lyric: [lyric],
  };

  /// Resolve the names actually present in [styleLines] so Dialogue references
  /// follow a Dial-based or renamed table. Roles missing from the table fall
  /// back to the built-in names.
  static StyleNames namesFor(Iterable<String> styleLines, {bool hdr = true}) {
    final found = <StyleRole, String>{};
    for (final raw in styleLines) {
      final parsed = AssStyle.tryParse(raw);
      if (parsed == null) continue;
      final role = roleOf(parsed.name);
      if (role == null || found.containsKey(role)) continue;
      found[role] = parsed.name;
    }
    String pick(StyleRole role) {
      final name = found[role] ?? StyleCatalog.name(role);
      return hdr ? name : sdrName(name);
    }

    return StyleNames(
      chinese: pick(StyleRole.chinese),
      foreign: pick(StyleRole.foreign),
      annotation: pick(StyleRole.annotation),
      lyric: pick(StyleRole.lyric),
    );
  }

  static bool isBuiltInStyles(Iterable<String> styleLines) {
    final lines = styleLines
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return lines.isEmpty || _sameLines(lines, defaultStyleLines);
  }

  static bool isLegacyBuiltInStyles(Iterable<String> styleLines) =>
      _sameLines(styleLines, legacyDefaultStyleLines);

  static bool isLegacyJpReferenceStyles(Iterable<String> styleLines) =>
      _sameLines(styleLines, legacyJpReferenceStyleLines);

  static bool _sameLines(Iterable<String> styleLines, List<String> expected) {
    final lines = styleLines
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (lines.isEmpty || lines.length != expected.length) return false;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i] != expected[i]) return false;
    }
    return true;
  }

  /// Style table + authored resolution for [mode]. A pristine built-in table
  /// switches to the Dial-based JP preset in [ProcessMode.jpMerge]; customized
  /// styles are always kept as authored.
  static ({List<String> lines, int baseResY}) effectiveStyles({
    required List<String> styleLines,
    required int baseResY,
    required ProcessMode mode,
  }) {
    if (mode == ProcessMode.jpMerge && isBuiltInStyles(styleLines)) {
      return (lines: jpReferenceStyleLines, baseResY: jpReferenceBaseResY);
    }
    return (lines: styleLines, baseResY: baseResY);
  }

  /// `中下HDRipad` → `中下SDRipad`. A name without an `HDR` token is returned
  /// unchanged, which keeps the transform idempotent.
  static String sdrName(String hdrName) {
    if (!hdrName.toUpperCase().contains('HDR')) return hdrName;
    return hdrName.replaceAll(RegExp('HDR', caseSensitive: false), 'SDR');
  }

  /// The style name Dialogue lines must reference for [role] in the given mode.
  static String nameFor(StyleRole role, {bool hdr = true}) {
    final base = name(role);
    return hdr ? base : sdrName(base);
  }

  /// Resolve a style name (built-in, Dial, HDR or SDR) back to its role.
  static StyleRole? roleOf(String styleName) {
    final lower = styleName.trim().toLowerCase();
    for (final entry in _aliases.entries) {
      for (final alias in entry.value) {
        if (lower == alias.toLowerCase() ||
            lower == sdrName(alias).toLowerCase()) {
          return entry.key;
        }
      }
    }
    return null;
  }

  /// Rewrite a `Style:` line for SDR output: `HDR`→`SDR` in the name and a pure
  /// white [StyleRole.chinese]/body colour. Everything else is copied verbatim,
  /// so the annotation karaoke colour and geometry stay as authored.
  ///
  /// Lines whose name is not one of the four known roles pass through untouched;
  /// that keeps hand-written styles usable and avoids duplicate `Style:` entries.
  static String sdrLine(String raw) {
    final parsed = AssStyle.tryParse(raw);
    if (parsed == null || roleOf(parsed.name) == null) return raw.trim();
    final fields = raw.trim().substring(6).trimLeft().split(',');
    if (fields.length < 4) return raw.trim();
    fields[0] = sdrName(parsed.name).trim();
    fields[3] = sdrPrimaryColour;
    return 'Style: ${fields.join(',')}';
  }

  /// Style table lines for the requested mode, de-duplicated by name.
  static List<String> linesFor(Iterable<String> styleLines, {bool hdr = true}) {
    final out = <String>[];
    final seen = <String>{};
    for (final raw in styleLines) {
      final line = hdr ? raw.trim() : sdrLine(raw);
      final parsed = AssStyle.tryParse(line);
      if (parsed == null) continue;
      if (!seen.add(parsed.name)) continue;
      out.add(line);
    }
    return out;
  }

  static String _fmtNum(double v) {
    final rounded = (v * 10).round() / 10;
    if (rounded == rounded.roundToDouble()) {
      return rounded.round().toString();
    }
    return rounded.toStringAsFixed(1);
  }

  /// Scale geometry fields (Fontsize/Outline/Shadow/MarginL/R/V) by [factor]
  /// so styles authored at one PlayRes keep the same on-screen proportions at
  /// another. Colour, alignment and everything else pass through verbatim;
  /// factor 1 leaves the line untouched.
  static String scaleLine(String raw, double factor) {
    final trimmed = raw.trim();
    if ((factor - 1.0).abs() < 0.0001) return trimmed;
    final parsed = AssStyle.tryParse(trimmed);
    if (parsed == null) return trimmed;
    final fields = trimmed.substring(6).trimLeft().split(',');
    if (fields.length < 23) return trimmed;
    double read(int i) => double.tryParse(fields[i].trim()) ?? 0;
    fields[2] = _fmtNum(read(2) * factor); // Fontsize
    fields[16] = _fmtNum(read(16) * factor); // Outline
    fields[17] = _fmtNum(read(17) * factor); // Shadow
    fields[19] = _fmtNum(read(19) * factor); // MarginL
    fields[20] = _fmtNum(read(20) * factor); // MarginR
    fields[21] = _fmtNum(read(21) * factor); // MarginV
    return 'Style: ${fields.join(',')}';
  }
}

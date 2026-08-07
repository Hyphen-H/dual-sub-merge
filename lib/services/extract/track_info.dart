class SubtitleTrackInfo {
  SubtitleTrackInfo({
    required this.id,
    required this.codec,
    this.language = '',
    this.title = '',
    this.isDefault = false,
    this.isForced = false,
    this.streamIndex,
  });

  /// mkvextract track id / or relative subtitle index for ffmpeg map
  final int id;
  final String codec;
  final String language;
  final String title;
  final bool isDefault;
  final bool isForced;
  /// absolute stream index for ffmpeg -map 0:N
  final int? streamIndex;

  bool get isAssText {
    final c = codec.toLowerCase();
    return c.contains('ass') ||
        c.contains('ssa') ||
        c.contains('substationalpha') ||
        c.contains('substation alpha');
  }

  String get textFileExtension {
    final c = codec.toLowerCase();
    if (isAssText) return '.ass';
    if (c.contains('vtt') || c.contains('webvtt')) return '.vtt';
    return '.srt';
  }

  bool get isText {
    final c = codec.toLowerCase();
    return c.contains('subrip') ||
        c.contains('srt') ||
        isAssText ||
        c.contains('webvtt') ||
        c.contains('mov_text') ||
        c.contains('text') ||
        c == 's_text/utf8' ||
        c == 's_text/ass' ||
        c == 's_text/ssa' ||
        c == 's_hdmv/pgs' // keep listed but not extractable as text
        ;
  }

  bool get isBitmap {
    final c = codec.toLowerCase();
    return c.contains('pgs') || c.contains('vobsub') || c.contains('dvd_subtitle') || c.contains('hdmv');
  }

  bool get isSdh {
    final t = '${title.toLowerCase()} ${language.toLowerCase()}';
    return t.contains('sdh') || t.contains('hearing') || RegExp(r'\bcc\b').hasMatch(t);
  }

  bool get isChinese {
    final lang = language.toLowerCase();
    final t = title.toLowerCase();
    if ({'chi', 'zho', 'zh', 'chs', 'cht', 'zh-cn', 'zh-tw', 'zh-hans', 'zh-hant'}.contains(lang)) {
      return true;
    }
    return RegExp(r'简|繁|中文|chs|cht|chinese|中字').hasMatch(t);
  }

  bool get isEnglish {
    final lang = language.toLowerCase();
    final t = title.toLowerCase();
    if ({'eng', 'en', 'en-us', 'en-gb'}.contains(lang)) return true;
    return RegExp(r'english|\beng\b').hasMatch(t);
  }

  bool get isCommentary {
    return title.toLowerCase().contains('comment');
  }

  String get label {
    final parts = <String>[
      '#$id',
      if (language.isNotEmpty) language,
      if (title.isNotEmpty) title,
      codec,
      if (isSdh) 'SDH',
      if (isForced) 'forced',
    ];
    return parts.join(' | ');
  }
}

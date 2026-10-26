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
        c ==
            's_hdmv/pgs' // keep listed but not extractable as text
            ;
  }

  bool get isBitmap {
    final c = codec.toLowerCase();
    return c.contains('pgs') ||
        c.contains('vobsub') ||
        c.contains('dvd_subtitle') ||
        c.contains('hdmv');
  }

  bool get isSdh {
    final t = '${title.toLowerCase()} ${language.toLowerCase()}';
    return t.contains('sdh') ||
        t.contains('hearing') ||
        RegExp(r'\bcc\b').hasMatch(t);
  }

  String get _langNorm => language.trim().toLowerCase().replaceAll('_', '-');

  bool get isChinese {
    final lang = _langNorm;
    if (_chineseLangCodes.contains(lang) ||
        lang.startsWith('zh-hans') ||
        lang.startsWith('zh-hant') ||
        lang.startsWith('zh-cn') ||
        lang.startsWith('zh-sg') ||
        lang.startsWith('zh-tw') ||
        lang.startsWith('zh-hk') ||
        lang.startsWith('zh-mo')) {
      return true;
    }
    return RegExp(
      r'简|簡|繁|中文|chs|cht|chinese|中字',
      caseSensitive: false,
    ).hasMatch(title);
  }

  bool get isSimplifiedChinese {
    if (_scriptFromLanguage == _ChineseScript.simplified) return true;
    if (_scriptFromLanguage == _ChineseScript.traditional) return false;
    return _scriptFromTitle == _ChineseScript.simplified;
  }

  bool get isTraditionalChinese {
    if (_scriptFromLanguage == _ChineseScript.traditional) return true;
    if (_scriptFromLanguage == _ChineseScript.simplified) return false;
    return _scriptFromTitle == _ChineseScript.traditional;
  }

  _ChineseScript? get _scriptFromLanguage {
    final lang = _langNorm;
    if (_simplifiedLangCodes.contains(lang) ||
        lang.startsWith('zh-hans') ||
        lang.startsWith('zh-cn') ||
        lang.startsWith('zh-sg')) {
      return _ChineseScript.simplified;
    }
    if (_traditionalLangCodes.contains(lang) ||
        lang.startsWith('zh-hant') ||
        lang.startsWith('zh-tw') ||
        lang.startsWith('zh-hk') ||
        lang.startsWith('zh-mo')) {
      return _ChineseScript.traditional;
    }
    return null;
  }

  _ChineseScript? get _scriptFromTitle {
    final simplified = RegExp(
      r'简|簡|chs|simplified',
      caseSensitive: false,
    ).hasMatch(title);
    final traditional = RegExp(
      r'繁|正體|正体|cht|big5|traditional',
      caseSensitive: false,
    ).hasMatch(title);
    if (simplified && !traditional) return _ChineseScript.simplified;
    if (traditional && !simplified) return _ChineseScript.traditional;
    return null;
  }

  static const _chineseLangCodes = {
    'chi',
    'zho',
    'zh',
    'chs',
    'cht',
    'zhs',
    'zht',
    'sc',
    'tc',
    'big5',
    'zh-cn',
    'zh-sg',
    'zh-tw',
    'zh-hk',
    'zh-mo',
    'zh-hans',
    'zh-hant',
  };

  static const _simplifiedLangCodes = {
    'chs',
    'sc',
    'zhs',
    'zh-cn',
    'zh-hans',
    'zh-sg',
  };

  static const _traditionalLangCodes = {
    'cht',
    'tc',
    'zht',
    'big5',
    'zh-tw',
    'zh-hk',
    'zh-hant',
    'zh-mo',
  };

  bool get isEnglish {
    final lang = language.toLowerCase();
    final t = title.toLowerCase();
    if (isDubtitle) return true;
    if ({'eng', 'en', 'en-us', 'en-gb'}.contains(lang)) return true;
    return RegExp(r'english|\beng\b').hasMatch(t);
  }

  bool get isDubtitle =>
      RegExp(r'dub[\s_-]*title', caseSensitive: false).hasMatch(title);

  bool get isJapanese {
    final lang = _langNorm;
    if (lang == 'jpn' ||
        lang == 'ja' ||
        lang == 'jp' ||
        lang == 'jap' ||
        lang.startsWith('ja-')) {
      return true;
    }
    return RegExp(
      r'日本語|日語|日语|日文|\bjpn\b|japanese',
      caseSensitive: false,
    ).hasMatch(title);
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

enum _ChineseScript { simplified, traditional }

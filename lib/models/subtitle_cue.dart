class SubtitleCue {
  SubtitleCue({
    required this.startMs,
    required this.endMs,
    required this.rawText,
    this.layer = 0,
    this.styleName = 'Default',
    this.name = '',
    this.effect = '',
    this.marginL = 0,
    this.marginR = 0,
    this.marginV = 0,
    this.sourceHadAn8 = false,
    this.isLyric = false,
    this.isAnnotation = false,
    this.outputStyle = '',
    this.text = '',
  });

  final int startMs;
  final int endMs;
  final String rawText;
  final int layer;
  final String styleName;
  final String name;
  final String effect;
  final int marginL;
  final int marginR;
  final int marginV;

  bool sourceHadAn8;
  bool isLyric;
  bool isAnnotation;
  String outputStyle;
  String text;

  SubtitleCue copyWith({
    int? startMs,
    int? endMs,
    String? rawText,
    String? text,
    bool? sourceHadAn8,
    bool? isLyric,
    bool? isAnnotation,
    String? outputStyle,
  }) {
    return SubtitleCue(
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      rawText: rawText ?? this.rawText,
      layer: layer,
      styleName: styleName,
      name: name,
      effect: effect,
      marginL: marginL,
      marginR: marginR,
      marginV: marginV,
      sourceHadAn8: sourceHadAn8 ?? this.sourceHadAn8,
      isLyric: isLyric ?? this.isLyric,
      isAnnotation: isAnnotation ?? this.isAnnotation,
      outputStyle: outputStyle ?? this.outputStyle,
      text: text ?? this.text,
    );
  }
}

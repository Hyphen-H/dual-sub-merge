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
    return AssStyle(name: name, line: line.startsWith('Style:') ? line : 'Style: $body');
  }
}

class StyleCatalog {
  static const chinese = '中下HDRipad';
  static const foreign = '英上HDRipad';
  static const annotation = 'annotationHDRipad';
  static const lyric = 'LyricHDRipad';

  static const List<String> defaultStyleLines = [
    'Style: 中下HDRipad,FZHei-B01,70,&H00828282,&H00B4B4B4,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,1,2,5,5,-55,134',
    'Style: 英上HDRipad,Microsoft YaHei,80,&H00828282,&H00B4B4B4,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,1,2,5,5,35,134',
    'Style: annotationHDRipad,FZHei-B01,60,&H00828282,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,1,8,0,0,60,1',
    'Style: LyricHDRipad,Microsoft YaHei,60,&H00828282,&H00C8C8C8,&H00000000,&H00000000,0,-1,0,0,100,100,0,0,1,2,1,8,0,0,60,1',
  ];

  static List<AssStyle> defaults() =>
      defaultStyleLines.map((e) => AssStyle.tryParse(e)!).toList();
}

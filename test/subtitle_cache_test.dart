import 'dart:io';

import 'package:dual_sub_merge/services/parse/subtitle_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

String _ass(String text) =>
    '[Script Info]\n'
    'ScriptType: v4.00+\n'
    '[V4+ Styles]\n'
    'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, '
    'OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, '
    'ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, '
    'MarginL, MarginR, MarginV, Encoding\n'
    'Style: Default,Arial,20,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,'
    '0,0,0,0,100,100,0,0,1,2,1,2,10,10,10,1\n'
    '[Events]\n'
    'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, '
    'Effect, Text\n'
    'Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,$text\n';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('subtitle-cache-');
    SubtitleLoader.clearCache();
  });

  tearDown(() async {
    SubtitleLoader.clearCache();
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test(
    'load reuses the parsed document and refreshes after a change',
    () async {
      final file = File(p.join(dir.path, 'Cache.ass'));
      await file.writeAsString(_ass('第一次'));

      final first = await SubtitleLoader.load(file);
      final second = await SubtitleLoader.load(file);
      expect(identical(first, second), isTrue);
      expect(first.cues.single.rawText, '第一次');

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await file.writeAsString(_ass('第二次内容更长'));

      final third = await SubtitleLoader.load(file);
      expect(identical(first, third), isFalse);
      expect(third.cues.single.rawText, '第二次内容更长');
    },
  );

  test('mayContainBilingual skips plain ASS without hard breaks', () async {
    final plain = File(p.join(dir.path, 'Plain.ass'));
    await plain.writeAsString(_ass('只是中文字幕'));
    expect(await SubtitleLoader.mayContainBilingual(plain), isFalse);

    final dual = File(p.join(dir.path, 'Dual.ass'));
    await dual.writeAsString(_ass(r'中文\NEnglish line'));
    expect(await SubtitleLoader.mayContainBilingual(dual), isTrue);

    final mixed = File(p.join(dir.path, 'Mixed.ass'));
    await mixed.writeAsString(_ass('中文 hello world again'));
    expect(await SubtitleLoader.mayContainBilingual(mixed), isTrue);
  });

  test('mayContainBilingual always parses SRT', () async {
    final srt = File(p.join(dir.path, 'Plain.srt'));
    await srt.writeAsString('1\n00:00:01,000 --> 00:00:02,000\n你好\n');
    expect(await SubtitleLoader.mayContainBilingual(srt), isTrue);
  });
}

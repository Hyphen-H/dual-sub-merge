import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:dual_sub_merge/models/ass_style.dart';
import 'package:dual_sub_merge/models/merge_options.dart';
import 'package:dual_sub_merge/models/subtitle_cue.dart';
import 'package:dual_sub_merge/models/track_role.dart';
import 'package:dual_sub_merge/services/bilingual_inline.dart';
import 'package:dual_sub_merge/services/blacklist.dart';
import 'package:dual_sub_merge/services/language_from_name.dart';
import 'package:dual_sub_merge/services/parse/ass_parser.dart';
import 'package:dual_sub_merge/services/parse/srt_parser.dart';
import 'package:dual_sub_merge/services/parse/subtitle_loader.dart';
import 'package:dual_sub_merge/services/parse/text_decoder.dart';
import 'package:dual_sub_merge/services/text_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TextPipeline', () {
    test('replaces \\N and keeps italic', () {
      final cue = SubtitleCue(
        startMs: 0,
        endMs: 1000,
        rawText: r'{\i1}Hello\NWorld{\i0}{\pos(1,2)}',
      );
      final out = TextPipeline.process(cue, TrackRole.foreign);
      expect(out.text.contains(r'\N'), isFalse);
      expect(out.text.contains(r'\pos'), isFalse);
      expect(out.text.contains(r'\i1'), isTrue);
      expect(out.text, contains('Hello World'));
    });

    test('converts HTML <i> to ASS italic', () {
      final cue = SubtitleCue(
        startMs: 0,
        endMs: 1000,
        rawText: r'<i>Delta Squad, we found the target.</i>',
      );
      final out = TextPipeline.process(cue, TrackRole.foreign);
      expect(out.text, r'{\i1}Delta Squad, we found the target.{\i0}');
      expect(out.text.contains('<i>'), isFalse);
    });

    test('converts <em> and mixed case', () {
      final cue = SubtitleCue(
        startMs: 0,
        endMs: 1000,
        rawText: r'Normal <I>italic</I> and <em>also</em>',
      );
      final out = TextPipeline.process(cue, TrackRole.foreign);
      expect(out.text, r'Normal {\i1}italic{\i0} and {\i1}also{\i0}');
    });

    test('an8 -> annotation style', () {
      final cue = SubtitleCue(
        startMs: 0,
        endMs: 1000,
        rawText: r'{\an8\fs14}地点名',
      );
      final out = TextPipeline.process(cue, TrackRole.chinese);
      expect(out.isAnnotation, isTrue);
      expect(out.outputStyle, StyleCatalog.annotation);
    });

    test('lyric star and music', () {
      final a = TextPipeline.process(
        SubtitleCue(startMs: 0, endMs: 1, rawText: '*歌词*'),
        TrackRole.chinese,
      );
      final b = TextPipeline.process(
        SubtitleCue(startMs: 0, endMs: 1, rawText: '♪塔哒!♪'),
        TrackRole.chinese,
      );
      expect(a.outputStyle, StyleCatalog.lyric);
      expect(b.outputStyle, StyleCatalog.lyric);
    });

    test('punctuation normalize', () {
      final cue = TextPipeline.process(
        SubtitleCue(startMs: 0, endMs: 1, rawText: '你好,世界！“引号”'),
        TrackRole.chinese,
      );
      expect(cue.text, contains('你好, 世界!'));
      expect(cue.text, contains('"引号"'));
      expect(cue.text.contains('！'), isFalse);
    });

    test('english comma spacing', () {
      final cue = TextPipeline.process(
        SubtitleCue(startMs: 0, endMs: 1, rawText: 'Hello,world,and you'),
        TrackRole.foreign,
      );
      expect(cue.text, 'Hello, world, and you');
      // thousands separator unchanged
      final num = TextPipeline.process(
        SubtitleCue(startMs: 0, endMs: 1, rawText: 'Score is 1,000 points'),
        TrackRole.foreign,
      );
      expect(num.text, 'Score is 1,000 points');
    });
  });

  group('Blacklist', () {
    test('removes credit lines only when matched', () {
      final f = BlacklistFilter(MergeOptions.defaultBlacklistRules);
      final credit =
          '本'
          '字幕'
          '仅供爱好者交流,严禁用于任何商业途径';
      final data = <SubtitleCue>[
        SubtitleCue(startMs: 0, endMs: 1, rawText: '翻译: 人人影视'),
        SubtitleCue(startMs: 0, endMs: 1, rawText: '这需要翻译成中文'),
        SubtitleCue(startMs: 0, endMs: 1, rawText: '校对：张三'),
        SubtitleCue(startMs: 0, endMs: 1, rawText: '他是校对员'),
        SubtitleCue(startMs: 0, endMs: 1, rawText: credit),
      ];

      final result = f.filter(data);
      expect(result.$2, 3);
      expect(result.$1.map((e) => e.rawText).toList(), ['这需要翻译成中文', '他是校对员']);
    });
  });

  group('LanguageFromName', () {
    test('filename tokens', () {
      expect(
        LanguageFromName.fromPath(r'a\show.S01E01.chs.ass'),
        TrackRole.chinese,
      );
      expect(
        LanguageFromName.fromPath(r'a\show.S01E01.eng.srt'),
        TrackRole.foreign,
      );
      expect(
        LanguageFromName.fromPath(r'a\show.S01E01.en.srt'),
        TrackRole.foreign,
      );
      expect(
        LanguageFromName.fromPath(r'a\Show-S01E01_ChineseSubtitle.ass'),
        TrackRole.chinese,
      );
      expect(
        LanguageFromName.fromPath(r'a\Show-S01E01_EnglishSubtitle.ass'),
        TrackRole.foreign,
      );
      expect(
        LanguageFromName.fromPath(r'a\Show-S01E01.chs+eng.ass'),
        TrackRole.unknown,
      );
      expect(
        LanguageFromName.fromPath(r'a\Slow.Horses.S05E05.t4.[eng].srt'),
        TrackRole.foreign,
      );
      expect(
        LanguageFromName.fromPath(r'a\Slow.Horses.S05E05.t8.[chi].srt'),
        TrackRole.chinese,
      );
    });

    test('content fallback uses dominant character body', () {
      expect(
        LanguageFromName.fromContent([
          'OK',
          '这是一整句中文字幕内容，用来判断主体语言。',
          '下一句仍然主要是中文对白。',
        ]),
        TrackRole.chinese,
      );
      expect(
        LanguageFromName.fromContent([
          '你好',
          'This is a full English subtitle line for language detection.',
          'Another English dialogue line dominates the body.',
        ]),
        TrackRole.foreign,
      );
    });

    test('normalize prefix', () {
      expect(
        LanguageFromName.normalizePrefix('Show.S02E01.chs.ass'),
        LanguageFromName.normalizePrefix('Show.S02E01.eng.srt'),
      );
      expect(
        LanguageFromName.normalizePrefix(
          'Slow.Horses.S05E05.t4.[eng].srt',
        ),
        LanguageFromName.normalizePrefix(
          'Slow.Horses.S05E05.t8.[chi].srt',
        ),
      );
    });
  });

  group('BilingualInline', () {
    test('detects dual line pattern with \\N', () {
      final cues = List.generate(
        10,
        (i) => SubtitleCue(
          startMs: i * 1000,
          endMs: i * 1000 + 500,
          rawText: r'{\fn楷体}中文句子{\r}\N{\fntahoma}English sentence.{\r}',
        ),
      );
      expect(BilingualInlineDetector.isBilingualInline(cues), isTrue);
    });

    test('detects single-line mixed CN+EN', () {
      final cues = List.generate(
        10,
        (i) => SubtitleCue(
          startMs: i * 1000,
          endMs: i * 1000 + 500,
          rawText:
              r'{\fn楷体}那么直截了当地说{\r}{\fntahoma}So let me get this straight.{\r}',
        ),
      );
      expect(BilingualInlineDetector.isBilingualInline(cues), isTrue);
    });
  });

  group('Parsers', () {
    List<int> utf16Bytes(String value, {required bool littleEndian}) {
      final bytes = <int>[
        if (littleEndian) 0xFF else 0xFE,
        if (littleEndian) 0xFE else 0xFF,
      ];
      for (final unit in value.codeUnits) {
        if (littleEndian) {
          bytes.add(unit & 0xFF);
          bytes.add(unit >> 8);
        } else {
          bytes.add(unit >> 8);
          bytes.add(unit & 0xFF);
        }
      }
      return bytes;
    }

    test('decodes UTF-16LE and UTF-16BE text', () {
      const text = '中文字幕';
      expect(
        SubtitleTextDecoder.decode(utf16Bytes(text, littleEndian: true)),
        text,
      );
      expect(
        SubtitleTextDecoder.decode(utf16Bytes(text, littleEndian: false)),
        text,
      );
    });

    test('srt parseFile decodes UTF-16LE extracted subtitle', () async {
      final dir = await Directory.systemTemp.createTemp(
        'dual-sub-merge-encoding-',
      );
      try {
        final file = File('${dir.path}${Platform.pathSeparator}sample.srt');
        await file.writeAsBytes(
          utf16Bytes(
            '1\r\n00:00:01,000 --> 00:00:02,000\r\n中文对白\r\n',
            littleEndian: true,
          ),
        );
        final doc = await SrtParser.parseFile(file);
        expect(doc.cues.single.rawText, '中文对白');
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('ass parseFile decodes UTF-16LE extracted subtitle', () async {
      const ass =
          '[Script Info]\r\n\r\n[Events]\r\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\r\nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,中文对白\r\n';
      final dir = await Directory.systemTemp.createTemp(
        'dual-sub-merge-encoding-',
      );
      try {
        final file = File('${dir.path}${Platform.pathSeparator}sample.ass');
        await file.writeAsBytes(utf16Bytes(ass, littleEndian: true));
        final doc = await AssParser.parseFile(file);
        expect(doc.cues.single.rawText, '中文对白');
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test(
      'detects ASS content despite an extracted srt suffix and repairs it',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'dual-sub-merge-ass-',
        );
        try {
          final file = File(
            '${dir.path}${Platform.pathSeparator}sample.extracted.srt',
          );
          await file.writeAsString(
            '[Script Info]\n\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,你好\n',
          );
          final doc = await SubtitleLoader.load(file);
          expect(doc.cues.single.rawText, '你好');

          final repaired = await SubtitleLoader.repairExtractedExtension(file);
          expect(p.extension(repaired.path), '.ass');
          expect(repaired.existsSync(), isTrue);
          expect(file.existsSync(), isFalse);
        } finally {
          await dir.delete(recursive: true);
        }
      },
    );

    test('srt parse', () {
      const s = '''
1
00:00:01,000 --> 00:00:02,000
Hello

2
00:00:03,000 --> 00:00:04,500
World
''';
      final doc = SrtParser.parse(s);
      expect(doc.cues.length, 2);
      expect(doc.cues.first.rawText, 'Hello');
    });

    test('ass parse dialogue', () {
      const s = '''
[Script Info]
PlayResX: 1920
PlayResY: 1080

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,20,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,2,2,10,10,10,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Hello, world
''';
      final doc = AssParser.parse(s);
      expect(doc.cues.length, 1);
      expect(doc.cues.first.rawText, 'Hello, world');
      expect(doc.playResX, 1920);
    });
  });
}

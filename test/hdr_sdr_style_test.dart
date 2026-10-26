import 'dart:io';

import 'package:dual_sub_merge/models/ass_style.dart';
import 'package:dual_sub_merge/models/merge_options.dart';
import 'package:dual_sub_merge/models/process_mode.dart';
import 'package:dual_sub_merge/models/subtitle_cue.dart';
import 'package:dual_sub_merge/models/track_role.dart';
import 'package:dual_sub_merge/services/parse/ass_writer.dart';
import 'package:dual_sub_merge/services/parse/style_resolver.dart';
import 'package:dual_sub_merge/services/text_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

List<String> _dialogues(String ass) =>
    ass.split('\n').where((l) => l.startsWith('Dialogue:')).toList();

void main() {
  group('sdrName', () {
    test('replaces HDR with SDR, keeping the rest of the name', () {
      expect(StyleCatalog.sdrName('中下HDRipad'), '中下SDRipad');
      expect(StyleCatalog.sdrName('英上HDRipad'), '英上SDRipad');
      expect(StyleCatalog.sdrName('annotationHDRipad'), 'annotationSDRipad');
      expect(StyleCatalog.sdrName('LyricHDRipad'), 'LyricSDRipad');
    });

    test('is idempotent when the name is already SDR', () {
      expect(StyleCatalog.sdrName('中下SDRipad'), '中下SDRipad');
      expect(StyleCatalog.sdrName('我的样式'), '我的样式');
    });

    test('is case-insensitive on the HDR token', () {
      expect(StyleCatalog.sdrName('lower-hdr-style'), 'lower-SDR-style');
    });
  });

  group('nameFor / roleOf round-trip', () {
    test('every role maps to an SDR name that resolves back', () {
      for (final role in StyleRole.values) {
        final hdrName = StyleCatalog.name(role);
        final sdrName = StyleCatalog.nameFor(role, hdr: false);
        expect(sdrName, isNot(hdrName));
        expect(StyleCatalog.roleOf(hdrName), role);
        expect(StyleCatalog.roleOf(sdrName), role);
      }
    });

    test('unknown names have no role', () {
      expect(StyleCatalog.roleOf('Something'), isNull);
    });
  });

  group('sdrLine', () {
    test('sets body colour to pure white and leaves other fields alone', () {
      final line = StyleCatalog.sdrLine(StyleCatalog.defaultStyleLines[0]);
      final fields = line.split(',');
      expect(fields[0], 'Style: 中下SDRipad');
      expect(fields[1], 'FZHei-B01');
      expect(fields[2], '70');
      expect(fields[3], '&H00FFFFFF');
      // Secondary / outline / geometry must be untouched.
      expect(fields[4], '&H4DFFFFFF');
      expect(
        fields.sublist(5, 12),
        StyleCatalog.defaultStyleLines[0].split(',').sublist(5, 12),
      );
      expect(fields.last, '134');
    });

    test('keeps the dimmed annotation karaoke colour', () {
      final line = StyleCatalog.sdrLine(StyleCatalog.defaultStyleLines[2]);
      final fields = line.split(',');
      expect(fields[0], 'Style: annotationSDRipad');
      expect(fields[3], '&H00FFFFFF');
      expect(fields[4], '&H4DFFFFFF');
    });

    test('passes through styles that are not one of the four roles', () {
      const custom =
          'Style: MyStyle,Arial,60,&H0000FFFF,&H00000000,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,2,2,5,5,-55,134';
      expect(StyleCatalog.sdrLine(custom), custom);
    });

    test('is idempotent-ish: SDR names resolve as the same role', () {
      final once = StyleCatalog.sdrLine(StyleCatalog.defaultStyleLines[3]);
      expect(once.startsWith('Style: LyricSDRipad,'), isTrue);
      expect(StyleCatalog.sdrLine(once), once);
    });
  });

  group('linesFor', () {
    test('drops duplicate style names, keeping the first', () {
      final lines = StyleCatalog.linesFor([
        'Style: 中下HDRipad,A,60,&H00828282,&H00000000,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,1,2,5,5,-55,134',
        'Style: 中下HDRipad,B,70,&H0000FFFF,&H00000000,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,1,2,5,5,-55,134',
      ]);
      expect(lines, hasLength(1));
      expect(lines.single.split(',')[1], 'A');
    });

    test('SDR pass does not collide with the HDR name', () {
      final lines = StyleCatalog.linesFor(
        StyleCatalog.defaultStyleLines,
        hdr: false,
      );
      expect(lines, hasLength(4));
      expect(lines.map((l) => AssStyle.tryParse(l)!.name).toSet(), {
        '中下SDRipad',
        '英上SDRipad',
        'annotationSDRipad',
        'LyricSDRipad',
      });
    });
  });

  group('TextPipeline.resolveStyle', () {
    test('keeps the priority order in SDR mode', () {
      final lyric = TextPipeline.resolveStyle(
        role: TrackRole.chinese,
        isLyric: true,
        isAnnotation: false,
        hdr: false,
      );
      final an8 = TextPipeline.resolveStyle(
        role: TrackRole.chinese,
        isLyric: false,
        isAnnotation: true,
        hdr: false,
      );
      final zh = TextPipeline.resolveStyle(
        role: TrackRole.chinese,
        isLyric: false,
        isAnnotation: false,
        hdr: false,
      );
      final en = TextPipeline.resolveStyle(
        role: TrackRole.foreign,
        isLyric: false,
        isAnnotation: false,
        hdr: false,
      );
      expect(lyric, 'LyricSDRipad');
      expect(an8, 'annotationSDRipad');
      expect(zh, '中下SDRipad');
      expect(en, '英上SDRipad');
    });

    test('defaults to HDR names', () {
      expect(
        TextPipeline.resolveStyle(
          role: TrackRole.chinese,
          isLyric: false,
          isAnnotation: false,
        ),
        '中下HDRipad',
      );
    });
  });

  group('AssWriter', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('ass-hdr-');
    });
    tearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    test('writes the HDR style table and references it', () async {
      final out = p.join(dir.path, 'hdr.ass');
      await AssWriter.write(
        path: out,
        cues: [
          TextPipeline.process(
            SubtitleCue(startMs: 0, endMs: 1000, rawText: '你好'),
            TrackRole.chinese,
          ),
        ],
        options: MergeOptions(),
        title: 't',
      );
      final body = await File(out).readAsString();
      expect(body, contains('Style: 中下HDRipad,'));
      expect(_dialogues(body).single, contains(',中下HDRipad,'));
    });

    test('writes the derived SDR table and references it', () async {
      final out = p.join(dir.path, 'sdr.ass');
      await AssWriter.write(
        path: out,
        cues: [
          TextPipeline.process(
            SubtitleCue(startMs: 0, endMs: 1000, rawText: '你好'),
            TrackRole.chinese,
            hdr: false,
          ),
        ],
        options: MergeOptions(hdrSubtitle: false),
        title: 't',
      );
      final body = await File(out).readAsString();
      expect(body, contains('Style: 中下SDRipad,'));
      expect(body, isNot(contains('中下HDRipad,')));
      expect(_dialogues(body).single, contains(',中下SDRipad,'));
    });

    test(
      'falls back to built-in defaults when styleLines are unusable',
      () async {
        final out = p.join(dir.path, 'fallback.ass');
        await AssWriter.write(
          path: out,
          cues: [
            TextPipeline.process(
              SubtitleCue(startMs: 0, endMs: 1000, rawText: '你好'),
              TrackRole.chinese,
              hdr: false,
            ),
          ],
          options: MergeOptions(hdrSubtitle: false, styleLines: const []),
          title: 't',
        );
        final body = await File(out).readAsString();
        expect(body, contains('Style: 中下SDRipad,'));
        expect(_dialogues(body).single, contains(',中下SDRipad,'));
      },
    );

    test('a legacy HDR-only style list still yields SDR styles', () async {
      final out = p.join(dir.path, 'legacy.ass');
      await AssWriter.write(
        path: out,
        cues: [
          TextPipeline.process(
            SubtitleCue(startMs: 0, endMs: 1000, rawText: '你好'),
            TrackRole.chinese,
            hdr: false,
          ),
        ],
        options: MergeOptions(
          hdrSubtitle: false,
          styleLines: StyleCatalog.defaultStyleLines,
        ),
        title: 't',
      );
      final body = await File(out).readAsString();
      expect(body, contains('Style: 中下SDRipad,'));
    });

    test('sort order is identical across modes', () async {
      Future<List<String>> orderOf(bool hdr) async {
        final out = p.join(dir.path, 'rank-$hdr.ass');
        await AssWriter.write(
          path: out,
          cues: [
            // Deliberately out of order: chinese first, lyric last.
            TextPipeline.process(
              SubtitleCue(startMs: 0, endMs: 1000, rawText: '{\\i1}*歌词*'),
              TrackRole.chinese,
              hdr: hdr,
            ),
            TextPipeline.process(
              SubtitleCue(startMs: 0, endMs: 1000, rawText: '正文'),
              TrackRole.chinese,
              hdr: hdr,
            ),
            TextPipeline.process(
              SubtitleCue(startMs: 0, endMs: 1000, rawText: '{\\an8}注解'),
              TrackRole.chinese,
              hdr: hdr,
            ),
          ],
          options: MergeOptions(hdrSubtitle: hdr),
          title: 't',
        );
        return _dialogues(
          await File(out).readAsString(),
        ).map((l) => l.split(',')[3]).toList();
      }

      final hdrOrder = await orderOf(true);
      final sdrOrder = await orderOf(false);
      expect(hdrOrder, ['LyricHDRipad', 'annotationHDRipad', '中下HDRipad']);
      expect(sdrOrder, ['LyricSDRipad', 'annotationSDRipad', '中下SDRipad']);
    });

    test('jpMerge writes the Dial table and references its names', () async {
      final options = MergeOptions(processMode: ProcessMode.jpMerge);
      final styles = StyleResolver.resolve(options);
      final out = p.join(dir.path, 'jp.ass');
      await AssWriter.write(
        path: out,
        cues: [
          TextPipeline.process(
            SubtitleCue(startMs: 0, endMs: 1000, rawText: '你好'),
            TrackRole.chinese,
            names: styles.names,
          ),
          TextPipeline.process(
            SubtitleCue(startMs: 0, endMs: 1000, rawText: 'こんにちは'),
            TrackRole.foreign,
            names: styles.names,
          ),
        ],
        options: options,
        title: 't',
      );
      final body = await File(out).readAsString();
      expect(body, contains('Style: Dial-CH,FZHei-B01,72,'));
      expect(body, contains('Style: Dial-JP,FOT-Rodin ProN B,48,'));
      expect(body, contains('Style: annotationHDRipad,'));
      expect(body, isNot(contains('Style: 中下HDRipad,')));
      final dialogueStyles = _dialogues(
        body,
      ).map((line) => line.split(',')[3]).toList();
      expect(dialogueStyles, containsAll(['Dial-CH', 'Dial-JP']));
    });

    test('jpMerge SDR keeps Dial names and whitens the body', () async {
      final options = MergeOptions(
        processMode: ProcessMode.jpMerge,
        hdrSubtitle: false,
      );
      final styles = StyleResolver.resolve(options);
      final out = p.join(dir.path, 'jp-sdr.ass');
      await AssWriter.write(
        path: out,
        cues: [
          TextPipeline.process(
            SubtitleCue(startMs: 0, endMs: 1000, rawText: '你好'),
            TrackRole.chinese,
            hdr: false,
            names: styles.names,
          ),
        ],
        options: options,
        title: 't',
      );
      final body = await File(out).readAsString();
      expect(body, contains('Style: Dial-CH,FZHei-B01,72,&H00FFFFFF,'));
      expect(_dialogues(body).single, contains(',Dial-CH,'));
    });

    test('jpMerge treats an8 as the normal role style', () async {
      final options = MergeOptions(processMode: ProcessMode.jpMerge);
      final styles = StyleResolver.resolve(options);
      final chinese = TextPipeline.process(
        SubtitleCue(startMs: 0, endMs: 1000, rawText: r'{\an8}你好'),
        TrackRole.chinese,
        names: styles.names,
        treatAn8AsAnnotation: options.an8AsAnnotation,
      );
      final foreign = TextPipeline.process(
        SubtitleCue(startMs: 0, endMs: 1000, rawText: r'{\an8}こんにちは'),
        TrackRole.foreign,
        names: styles.names,
        treatAn8AsAnnotation: options.an8AsAnnotation,
      );

      expect(chinese.sourceHadAn8, isTrue);
      expect(chinese.isAnnotation, isFalse);
      expect(chinese.outputStyle, StyleCatalog.dialChinese);
      expect(foreign.outputStyle, StyleCatalog.dialForeign);

      final out = p.join(dir.path, 'jp-an8.ass');
      await AssWriter.write(
        path: out,
        cues: [chinese, foreign],
        options: options,
        title: 't',
      );
      final body = await File(out).readAsString();
      expect(body, contains('Style: annotationHDRipad,'));
      expect(
        _dialogues(body).map((line) => line.split(',')[3]),
        containsAll([StyleCatalog.dialChinese, StyleCatalog.dialForeign]),
      );
    });

    test('an8 annotation option uses the annotation style', () async {
      final options = MergeOptions(
        processMode: ProcessMode.jpMerge,
        an8AsAnnotation: true,
      );
      final styles = StyleResolver.resolve(options);
      final chinese = TextPipeline.process(
        SubtitleCue(startMs: 0, endMs: 1000, rawText: r'{\an8}你好'),
        TrackRole.chinese,
        names: styles.names,
        treatAn8AsAnnotation: options.an8AsAnnotation,
      );

      expect(chinese.sourceHadAn8, isTrue);
      expect(chinese.isAnnotation, isTrue);
      expect(chinese.outputStyle, StyleCatalog.annotation);

      final out = p.join(dir.path, 'jp-an8-annotation.ass');
      await AssWriter.write(
        path: out,
        cues: [chinese],
        options: options,
        title: 't',
      );
      final body = await File(out).readAsString();
      expect(_dialogues(body).single, contains(',annotationHDRipad,'));
    });
  });

  group('StyleResolver', () {
    test('jpMerge uses Dial names at 720p base for pristine styles', () {
      final r = StyleResolver.resolve(
        MergeOptions(processMode: ProcessMode.jpMerge),
      );
      expect(r.baseResY, 720);
      expect(r.names.chinese, StyleCatalog.dialChinese);
      expect(r.names.foreign, StyleCatalog.dialForeign);
      expect(r.names.annotation, StyleCatalog.annotation);
      expect(r.names.lyric, StyleCatalog.lyric);
      expect(r.lines.any((line) => line.startsWith('Style: Dial-CH,')), isTrue);
      expect(
        r.lines.any((line) => line.startsWith('Style: annotationHDRipad,')),
        isTrue,
      );
    });

    test('jpMerge leaves custom styles untouched', () {
      const custom =
          'Style: 中下HDRipad,FZHei-B01,70,&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,1,2,5,5,-55,134';
      final r = StyleResolver.resolve(
        MergeOptions(
          processMode: ProcessMode.jpMerge,
          styleLines: const [custom],
          styleBaseResY: 1080,
        ),
      );
      expect(r.baseResY, 1080);
      expect(r.names.chinese, StyleCatalog.chinese);
      expect(r.lines.single, custom);
    });

    test('merge mode keeps the built-in table at 1080p', () {
      final r = StyleResolver.resolve(MergeOptions());
      expect(r.baseResY, 1080);
      expect(r.names.chinese, StyleCatalog.chinese);
      expect(r.names.foreign, StyleCatalog.foreign);
    });

    test('SDR derivation keeps Dial names and renames HDR roles', () {
      final r = StyleResolver.resolve(
        MergeOptions(processMode: ProcessMode.jpMerge, hdrSubtitle: false),
      );
      expect(r.names.chinese, StyleCatalog.dialChinese);
      expect(r.names.foreign, StyleCatalog.dialForeign);
      expect(r.names.annotation, 'annotationSDRipad');
      expect(r.names.lyric, 'LyricSDRipad');
    });
  });
}

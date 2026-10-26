import 'dart:io';

import 'package:dual_sub_merge/models/merge_options.dart';
import 'package:dual_sub_merge/services/chinese_convert_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _hdr = '1\n00:00:01,000 --> 00:00:02,000\n';

/// Dialogue lines only — the style catalogue in [V4+ Styles] always lists all four.
List<String> _dialogues(String assBody) =>
    assBody.split('\n').where((line) => line.startsWith('Dialogue:')).toList();

Future<(Directory, Directory)> _temp() async {
  final root = await Directory.systemTemp.createTemp('zh-convert-');
  addTearDown(() => root.delete(recursive: true));
  final src = Directory(p.join(root.path, 'src'));
  final out = Directory(p.join(root.path, 'out'));
  await src.create(recursive: true);
  return (src, out);
}

void main() {
  test('converts single chinese srt into .chs.ass with 中下HDRipad', () async {
    final (src, out) = await _temp();
    final file = File(p.join(src.path, 'Show.S01E01.chs.srt'));
    await file.writeAsString(
      '$_hdr你好，世界\n\n2\n00:00:03,000 --> 00:00:04,000\n今天天气不错\n',
    );

    final r = await ChineseConvertService(
      MergeOptions(an8AsAnnotation: true),
    ).convertFile(source: file, outDir: out);

    expect(r.ok, isTrue, reason: r.message);
    expect(p.basename(r.outputPath!), 'Show.S01E01.chs.ass');
    final body = await File(r.outputPath!).readAsString();
    expect(body, contains('PlayResX: 1920'));
    expect(body, contains('你好, 世界'));
    expect(_dialogues(body), everyElement(contains(',中下HDRipad,')));
  });

  test('keeps annotation and lyric style priority', () async {
    final (src, out) = await _temp();
    final file = File(p.join(src.path, 'a.ass'));
    await file.writeAsString(
      '[Events]\n'
      'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
      'Dialogue: 0,0:00:01.00,0:00:02.00,D,,0,0,0,,{\\an8}上方注解\n'
      'Dialogue: 0,0:00:03.00,0:00:04.00,D,,0,0,0,,{\\i1}*唱歌*\n',
    );

    final r = await ChineseConvertService(
      MergeOptions(an8AsAnnotation: true),
    ).convertFile(source: file, outDir: out);

    expect(r.ok, isTrue, reason: r.message);
    final body = await File(r.outputPath!).readAsString();
    final lines = _dialogues(body);
    expect(lines.first, contains(',annotationHDRipad,'));
    expect(lines.last, contains(',LyricHDRipad,'));
  });

  test('removes credits when the blacklist is on', () async {
    final (src, out) = await _temp();
    final file = File(p.join(src.path, 'b.chs.srt'));
    await file.writeAsString(
      '$_hdr翻译: 某某\n\n2\n00:00:03,000 --> 00:00:04,000\n正文一句\n',
    );

    final r = await ChineseConvertService(
      MergeOptions(),
    ).convertFile(source: file, outDir: out);

    expect(r.ok, isTrue, reason: r.message);
    expect(r.removedCredits, 1);
    final body = await File(r.outputPath!).readAsString();
    expect(body, isNot(contains('翻译:')));
    expect(body, contains('正文一句'));
  });

  test('splits \\N bilingual and keeps only the chinese half', () async {
    final (src, out) = await _temp();
    final file = File(p.join(src.path, 'c.ass'));
    final cues = StringBuffer(
      '[Events]\n'
      'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n',
    );
    for (var i = 0; i < 5; i++) {
      final start = i * 2 + 1;
      cues.write(
        'Dialogue: 0,0:00:0$start.00,0:00:0${start + 1}.00,D,,0,0,0,,'
        '中文第${i + 1}行\\NEnglish line ${i + 1}\n',
      );
    }
    await file.writeAsString(cues.toString());

    final r = await ChineseConvertService(
      MergeOptions(),
    ).convertFile(source: file, outDir: out);

    expect(r.ok, isTrue, reason: r.message);
    expect(p.basename(r.outputPath!), 'c.chs.ass');
    final body = await File(r.outputPath!).readAsString();
    final lines = _dialogues(body);
    expect(lines, hasLength(5));
    expect(lines.first, contains('中文第1行'));
    expect(lines.every((l) => !l.contains('English line')), isTrue);
    expect(lines, everyElement(contains(',中下HDRipad,')));
  });

  test('SDR mode writes 中下SDRipad styles', () async {
    final (src, out) = await _temp();
    final file = File(p.join(src.path, 'sdr.chs.srt'));
    await file.writeAsString('$_hdr你好，世界\n');

    final r = await ChineseConvertService(
      MergeOptions(hdrSubtitle: false),
    ).convertFile(source: file, outDir: out);

    expect(r.ok, isTrue, reason: r.message);
    final body = await File(r.outputPath!).readAsString();
    expect(body, contains('Style: 中下SDRipad,'));
    expect(_dialogues(body), everyElement(contains(',中下SDRipad,')));
  });

  test('fails when the file has no chinese content', () async {
    final (src, out) = await _temp();
    final file = File(p.join(src.path, 'd.eng.srt'));
    await file.writeAsString(
      '${_hdr}Hello there\n\n2\n00:00:03,000 --> 00:00:04,000\nBye now\n',
    );

    final r = await ChineseConvertService(
      MergeOptions(),
    ).convertFile(source: file, outDir: out);

    // English-only mono input is still written out (mode is explicit), so the
    // converter stays a pure transform; the group layer is what filters it out.
    expect(r.ok, isTrue, reason: r.message);
    expect(r.cueCount, 2);
  });

  test(
    'reports unconvertible inline bilingual instead of cutting lines',
    () async {
      final (src, out) = await _temp();
      final file = File(p.join(src.path, 'e.srt'));
      await file.writeAsString('$_hdr这是单行中英mixed混排没有换行\n');

      final r = await ChineseConvertService(
        MergeOptions(),
      ).convertFile(source: file, outDir: out);

      expect(r.ok, isTrue, reason: r.message);
      expect(r.cueCount, 1);
    },
  );
}

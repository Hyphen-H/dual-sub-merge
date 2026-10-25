import 'dart:io';

import 'package:dual_sub_merge/models/merge_options.dart';
import 'package:dual_sub_merge/models/process_mode.dart';
import 'package:dual_sub_merge/services/merge_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('merge writes into outputDir and creates dual-sub-merged', () async {
    final root = await Directory.systemTemp.createTemp('dsm-out-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    await File(
      p.join(root.path, 'Show.S01E01.chs.srt'),
    ).writeAsString('1\n00:00:01,000 --> 00:00:02,000\n你好世界\n');
    await File(
      p.join(root.path, 'Show.S01E01.eng.srt'),
    ).writeAsString('1\n00:00:01,000 --> 00:00:02,000\nHello world\n');

    final outDir = Directory(p.join(root.path, MergeOptions.mergedSubdirName));
    expect(outDir.existsSync(), isFalse);

    final svc = MergeService(options: MergeOptions(removeCredits: false));
    final r = await svc.run(root, outputDir: outDir);

    expect(r.successCount, 1);
    expect(outDir.existsSync(), isTrue);
    final out = File(p.join(outDir.path, 'Show.S01E01.chs+eng.ass'));
    expect(out.existsSync(), isTrue);
    expect(
      File(p.join(root.path, 'Show.S01E01.chs+eng.ass')).existsSync(),
      isFalse,
    );
  });

  test('merge defaults outputDir to input when omitted', () async {
    final root = await Directory.systemTemp.createTemp('dsm-in-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    await File(
      p.join(root.path, 'Ep.chs.srt'),
    ).writeAsString('1\n00:00:01,000 --> 00:00:02,000\n中文\n');
    await File(
      p.join(root.path, 'Ep.eng.srt'),
    ).writeAsString('1\n00:00:01,000 --> 00:00:02,000\nEN\n');

    final svc = MergeService(options: MergeOptions(removeCredits: false));
    final r = await svc.run(root);
    expect(r.successCount, 1);
    expect(File(p.join(root.path, 'Ep.chs+eng.ass')).existsSync(), isTrue);
  });

  test('merge names output .chs+jpn.ass for Japanese foreign file', () async {
    final root = await Directory.systemTemp.createTemp('dsm-jpn-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    await File(
      p.join(root.path, 'Anime.chs.srt'),
    ).writeAsString('1\n00:00:01,000 --> 00:00:02,000\n我不知道\n');
    await File(
      p.join(root.path, 'Anime.jpn.srt'),
    ).writeAsString('1\n00:00:01,000 --> 00:00:02,000\nそれは知らない、知ってるよ\n');

    final svc = MergeService(options: MergeOptions(removeCredits: false));
    final r = await svc.run(root);
    expect(r.successCount, 1);
    expect(File(p.join(root.path, 'Anime.chs+jpn.ass')).existsSync(), isTrue);
  });

  test('merge tags untagged Japanese file as jpn via content', () async {
    final root = await Directory.systemTemp.createTemp('dsm-jpnc-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    await File(
      p.join(root.path, 'Film.chs.srt'),
    ).writeAsString('1\n00:00:01,000 --> 00:00:02,000\n这是中文\n');
    await File(
      p.join(root.path, 'Film.srt'),
    ).writeAsString('1\n00:00:01,000 --> 00:00:02,000\nすみません、これは日本語の字幕です\n');

    final svc = MergeService(options: MergeOptions(removeCredits: false));
    final r = await svc.run(root);
    expect(r.successCount, 1);
    expect(File(p.join(root.path, 'Film.chs+jpn.ass')).existsSync(), isTrue);
  });

  test('jpMerge writes .chs+jpn.ass with Dial styles only', () async {
    final root = await Directory.systemTemp.createTemp('dsm-jpmerge-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    await File(
      p.join(root.path, 'Anime.S01E01.chs.srt'),
    ).writeAsString('1\n00:00:01,000 --> 00:00:02,000\n我不知道\n');
    await File(
      p.join(root.path, 'Anime.S01E01.jpn.srt'),
    ).writeAsString('1\n00:00:01,000 --> 00:00:02,000\nそれは知らない\n');

    final svc = MergeService(
      options: MergeOptions(
        removeCredits: false,
        processMode: ProcessMode.jpMerge,
      ),
    );
    final r = await svc.run(root);

    expect(r.successCount, 1);
    final out = File(p.join(root.path, 'Anime.S01E01.chs+jpn.ass'));
    expect(out.existsSync(), isTrue);
    final body = await out.readAsString();
    expect(body, contains('Style: Dial-CH,HYQiHei-65S,72,'));
    expect(body, contains('Style: Dial-JP,FOT-Rodin ProN B,48,'));
    expect(body, isNot(contains('Style: 中下HDRipad,')));
    final styles = body
        .split('\n')
        .where((line) => line.startsWith('Dialogue:'))
        .map((line) => line.split(',')[3])
        .toList();
    expect(styles, containsAll(['Dial-CH', 'Dial-JP']));
  });

  test('jpMerge skips a pair whose foreign side is not Japanese', () async {
    final root = await Directory.systemTemp.createTemp('dsm-jpskip-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    await File(
      p.join(root.path, 'Show.chs.srt'),
    ).writeAsString('1\n00:00:01,000 --> 00:00:02,000\n你好\n');
    await File(
      p.join(root.path, 'Show.eng.srt'),
    ).writeAsString('1\n00:00:01,000 --> 00:00:02,000\nHello\n');

    final svc = MergeService(
      options: MergeOptions(
        removeCredits: false,
        processMode: ProcessMode.jpMerge,
      ),
    );
    final r = await svc.run(root);

    expect(r.successCount, 0);
    expect(r.failCount, 1);
    expect(File(p.join(root.path, 'Show.chs+jpn.ass')).existsSync(), isFalse);
  });
}

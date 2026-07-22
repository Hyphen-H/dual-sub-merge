import 'dart:io';

import 'package:dual_sub_merge/models/merge_options.dart';
import 'package:dual_sub_merge/services/merge_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('merge writes into outputDir and creates dual-sub-merged', () async {
    final root = await Directory.systemTemp.createTemp('dsm-out-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    await File(p.join(root.path, 'Show.S01E01.chs.srt')).writeAsString(
      '1\n00:00:01,000 --> 00:00:02,000\n你好世界\n',
    );
    await File(p.join(root.path, 'Show.S01E01.eng.srt')).writeAsString(
      '1\n00:00:01,000 --> 00:00:02,000\nHello world\n',
    );

    final outDir = Directory(p.join(root.path, MergeOptions.mergedSubdirName));
    expect(outDir.existsSync(), isFalse);

    final svc = MergeService(
      options: MergeOptions(extractFromVideo: false, removeCredits: false),
    );
    final r = await svc.run(root, outputDir: outDir);

    expect(r.successCount, 1);
    expect(outDir.existsSync(), isTrue);
    final out = File(p.join(outDir.path, 'Show.S01E01.chs+eng.ass'));
    expect(out.existsSync(), isTrue);
    expect(File(p.join(root.path, 'Show.S01E01.chs+eng.ass')).existsSync(), isFalse);
  });

  test('merge defaults outputDir to input when omitted', () async {
    final root = await Directory.systemTemp.createTemp('dsm-in-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    await File(p.join(root.path, 'Ep.chs.srt')).writeAsString(
      '1\n00:00:01,000 --> 00:00:02,000\n中文\n',
    );
    await File(p.join(root.path, 'Ep.eng.srt')).writeAsString(
      '1\n00:00:01,000 --> 00:00:02,000\nEN\n',
    );

    final svc = MergeService(
      options: MergeOptions(extractFromVideo: false, removeCredits: false),
    );
    final r = await svc.run(root);
    expect(r.successCount, 1);
    expect(File(p.join(root.path, 'Ep.chs+eng.ass')).existsSync(), isTrue);
  });
}

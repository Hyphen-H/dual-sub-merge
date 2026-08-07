import 'dart:io';

import 'package:dual_sub_merge/models/match_group.dart';
import 'package:dual_sub_merge/models/merge_options.dart';
import 'package:dual_sub_merge/services/file_matcher.dart';
import 'package:dual_sub_merge/services/merge_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'overlapping scan directories do not duplicate extracted subtitles',
    () async {
      final root = await Directory.systemTemp.createTemp('matcher-overlap-');
      addTearDown(() => root.delete(recursive: true));
      final extract = Directory(p.join(root.path, 'dual-sub-merge-extract'));
      await extract.create();
      await File(
        p.join(extract.path, 'Arcane.S01E01.chs.srt'),
      ).writeAsString('1\n00:00:01,000 --> 00:00:02,000\n你好\n');
      await File(
        p.join(extract.path, 'Arcane.S01E01.eng.srt'),
      ).writeAsString('1\n00:00:01,000 --> 00:00:02,000\nHello\n');

      final groups = await FileMatcher.scanDirectories([root, extract]);

      expect(groups, hasLength(1));
      expect(groups.single.kind, GroupKind.pair);
      expect(groups.single.status, GroupStatus.ready);
    },
  );

  test('pairs bracketed language tracks with different track numbers', () async {
    final root = await Directory.systemTemp.createTemp('matcher-bracketed-');
    addTearDown(() => root.delete(recursive: true));
    const stems = [
      'Slow.Horses.S05E05.Circus.2160p.ATVP.WEB-DL.DDP5.1.Atmos.H.265-FLUX',
      'Slow.Horses.S05E06.Scars.2160p.ATVP.WEB-DL.DDP5.1.Atmos.H.265-FLUX',
    ];
    final files = <File>[];
    for (final stem in stems) {
      files.add(
        await File(p.join(root.path, '$stem.t8.[chi].srt')).writeAsString(
          '1\n00:00:01,000 --> 00:00:02,000\n你好，世界。\n',
        ),
      );
      files.add(
        await File(p.join(root.path, '$stem.t4.[eng].srt')).writeAsString(
          '1\n00:00:01,000 --> 00:00:02,000\nHello, world.\n',
        ),
      );
    }

    final groups = await FileMatcher.scanFiles(files);

    expect(groups, hasLength(2));
    expect(groups.every((group) => group.status == GroupStatus.ready), isTrue);
    expect(groups.every((group) => group.chinese != null), isTrue);
    expect(groups.every((group) => group.foreign != null), isTrue);
  });

  test(
    'merge uses explicitly selected subtitle files without rescanning siblings',
    () async {
      final root = await Directory.systemTemp.createTemp('matcher-files-');
      addTearDown(() => root.delete(recursive: true));
      final chs = File(p.join(root.path, 'Arcane.S01E01.chs.srt'));
      final eng = File(p.join(root.path, 'Arcane.S01E01.eng.srt'));
      await chs.writeAsString('1\n00:00:01,000 --> 00:00:02,000\n你好\n');
      await eng.writeAsString('1\n00:00:01,000 --> 00:00:02,000\nHello\n');
      await File(
        p.join(root.path, 'Arcane.S01E01.chs.ass'),
      ).writeAsString('[Script Info]\n[V4+ Styles]\n[Events]\n');
      final groups = await FileMatcher.scanFiles([chs, eng]);
      final output = Directory(p.join(root.path, 'output'));

      final result = await MergeService(
        options: MergeOptions(removeCredits: false),
      ).run(root, outputDir: output, sourceGroups: groups);

      expect(result.successCount, 1);
      expect(
        File(p.join(output.path, 'Arcane.S01E01.chs+eng.ass')).existsSync(),
        isTrue,
      );
    },
  );

  test(
    'explicit videos with the same name in different folders stay distinct',
    () async {
      final root = await Directory.systemTemp.createTemp('matcher-videos-');
      addTearDown(() => root.delete(recursive: true));
      final firstDir = Directory(p.join(root.path, 'first'))..createSync();
      final secondDir = Directory(p.join(root.path, 'second'))..createSync();
      final first = File(p.join(firstDir.path, 'Episode01.mkv'))..createSync();
      final second = File(p.join(secondDir.path, 'Episode01.mkv'))
        ..createSync();

      final groups = await FileMatcher.scanFiles([first, second]);

      expect(groups.where((group) => group.video != null), hasLength(2));
      expect(
        groups.map((group) => group.video?.path).whereType<String>().toSet(),
        {first.path, second.path},
      );
    },
  );
}

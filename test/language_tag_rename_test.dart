import 'dart:io';

import 'package:dual_sub_merge/models/match_group.dart';
import 'package:dual_sub_merge/models/track_role.dart';
import 'package:dual_sub_merge/services/language_from_name.dart';
import 'package:dual_sub_merge/services/language_tag_rename_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('hasTrailingLanguageTag', () {
    test('detects tagged names', () {
      expect(LanguageFromName.hasTrailingLanguageTag(r'a\Show.chs.srt'), isTrue);
      expect(LanguageFromName.hasTrailingLanguageTag(r'a\Show.eng.ass'), isTrue);
      expect(LanguageFromName.hasTrailingLanguageTag(r'a\Show.en.srt'), isTrue);
    });

    test('untagged names', () {
      expect(LanguageFromName.hasTrailingLanguageTag(r'a\Show.S01E01.srt'), isFalse);
      expect(LanguageFromName.hasTrailingLanguageTag(r'a\episode.ass'), isFalse);
      expect(LanguageFromName.hasTrailingLanguageTag(r'a\My.Movie.srt'), isFalse);
    });
  });

  test('rename moves untagged files into chs-sub / eng-sub', () async {
    final root = await Directory.systemTemp.createTemp('dsm-tag-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    final zhSrc = File(p.join(root.path, 'Show.S01E01A.srt'));
    final enSrc = File(p.join(root.path, 'Show.S01E01B.srt'));
    await zhSrc.writeAsString('1\n00:00:01,000 --> 00:00:02,000\n你好\n');
    await enSrc.writeAsString('1\n00:00:01,000 --> 00:00:02,000\nHello\n');

    final g = MatchGroup(
      prefix: 'show.s01e01',
      displayPrefix: 'Show.S01E01',
      chinese: SubtitleFileRef(file: zhSrc, role: TrackRole.chinese),
      foreign: SubtitleFileRef(file: enSrc, role: TrackRole.foreign),
      kind: GroupKind.pair,
      status: GroupStatus.ready,
    );

    final r = await LanguageTagRenameService().renameGroups(
      inputDir: root,
      groups: [g],
    );

    expect(r.renamedCount, 2);
    expect(zhSrc.existsSync(), isFalse);
    expect(enSrc.existsSync(), isFalse);

    final zhOut = File(p.join(root.path, 'chs-sub', 'Show.S01E01A.chs.srt'));
    final enOut = File(p.join(root.path, 'eng-sub', 'Show.S01E01B.eng.srt'));
    expect(zhOut.existsSync(), isTrue);
    expect(enOut.existsSync(), isTrue);
    expect(g.chinese!.file.path, zhOut.path);
    expect(g.foreign!.file.path, enOut.path);

    // already tagged → skip
    final r2 = await LanguageTagRenameService().renameGroups(
      inputDir: root,
      groups: [g],
    );
    expect(r2.renamedCount, 0);
  });

  test('skips files that already have language tags', () async {
    final root = await Directory.systemTemp.createTemp('dsm-tag2-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    final zh = File(p.join(root.path, 'Ep.chs.srt'));
    await zh.writeAsString('1\n00:00:01,000 --> 00:00:02,000\n中\n');
    final g = MatchGroup(
      prefix: 'ep',
      chinese: SubtitleFileRef(file: zh, role: TrackRole.chinese),
    );
    final r = await LanguageTagRenameService().renameGroups(
      inputDir: root,
      groups: [g],
    );
    expect(r.renamedCount, 0);
    expect(zh.existsSync(), isTrue);
  });
}

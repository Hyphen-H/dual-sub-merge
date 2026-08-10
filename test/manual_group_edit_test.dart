import 'dart:io';

import 'package:dual_sub_merge/models/match_group.dart';
import 'package:dual_sub_merge/models/track_role.dart';
import 'package:dual_sub_merge/services/file_matcher.dart';
import 'package:dual_sub_merge/services/manual_group_edit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('setFileRole swaps chinese and foreign slots', () {
    final zh = File(r'C:\tmp\show.chs.srt');
    final en = File(r'C:\tmp\show.eng.srt');
    final g = MatchGroup(
      prefix: 'show',
      displayPrefix: 'show',
      chinese: SubtitleFileRef(file: zh, role: TrackRole.chinese),
      foreign: SubtitleFileRef(file: en, role: TrackRole.foreign),
      kind: GroupKind.pair,
      status: GroupStatus.ready,
    );

    ManualGroupEdit.setFileRole(g, zh.path, TrackRole.foreign);

    expect(g.chinese?.file.path, en.path);
    expect(g.foreign?.file.path, zh.path);
    expect(g.chinese?.role, TrackRole.chinese);
    expect(g.foreign?.role, TrackRole.foreign);
    expect(g.status, GroupStatus.ready);
  });

  test('setFileRole marks unknown and refreshes missing status', () {
    final zh = File(r'C:\tmp\ep.chs.srt');
    final en = File(r'C:\tmp\ep.eng.srt');
    final g = MatchGroup(
      prefix: 'ep',
      chinese: SubtitleFileRef(file: zh, role: TrackRole.chinese),
      foreign: SubtitleFileRef(file: en, role: TrackRole.foreign),
      kind: GroupKind.pair,
      status: GroupStatus.ready,
    );

    ManualGroupEdit.setFileRole(g, en.path, TrackRole.unknown);

    expect(g.foreign?.role, TrackRole.unknown);
    expect(g.status, isNot(GroupStatus.ready));
  });

  test('setKind converts pair to bilingualFile and back', () {
    final src = File(r'C:\tmp\dual.ass');
    final g = MatchGroup(
      prefix: 'dual',
      chinese: SubtitleFileRef(file: src, role: TrackRole.chinese),
      kind: GroupKind.pair,
      status: GroupStatus.missingForeign,
    );

    ManualGroupEdit.setKind(g, GroupKind.bilingualFile);
    expect(g.kind, GroupKind.bilingualFile);
    expect(g.bilingualSource?.path, src.path);
    expect(g.chinese, isNull);
    expect(g.status, GroupStatus.bilingualReady);

    ManualGroupEdit.setKind(g, GroupKind.pair);
    expect(g.kind, GroupKind.pair);
    expect(g.bilingualSource, isNull);
    expect(g.chinese?.file.path, src.path);
  });

  test('applyOverrides restores roles and kind after rescan keys', () async {
    final root = await Directory.systemTemp.createTemp('manual-override-');
    addTearDown(() => root.delete(recursive: true));
    // Filename tags pair as chs/eng; overrides force a swap.
    final chs = File(p.join(root.path, 'Show.S01E01.chs.srt'));
    final eng = File(p.join(root.path, 'Show.S01E01.eng.srt'));
    await chs.writeAsString('1\n00:00:01,000 --> 00:00:02,000\n你好世界\n');
    await eng.writeAsString('1\n00:00:01,000 --> 00:00:02,000\nHello world\n');

    final groups = await FileMatcher.scanFiles([chs, eng]);
    expect(groups, hasLength(1));
    expect(groups.single.chinese?.file.path, chs.path);

    final roles = <String, TrackRole>{
      ManualGroupEdit.pathKey(chs.path): TrackRole.foreign,
      ManualGroupEdit.pathKey(eng.path): TrackRole.chinese,
    };
    final kinds = <String, GroupKind>{
      ManualGroupEdit.pathKey(chs.path): GroupKind.pair,
    };

    ManualGroupEdit.applyOverrides(
      groups,
      rolesByPath: roles,
      kindByPath: kinds,
    );

    expect(groups.single.kind, GroupKind.pair);
    expect(groups.single.chinese?.file.path, eng.path);
    expect(groups.single.foreign?.file.path, chs.path);
    expect(groups.single.status, GroupStatus.ready);

    final again = await FileMatcher.scanFiles([chs, eng]);
    ManualGroupEdit.applyOverrides(
      again,
      rolesByPath: roles,
      kindByPath: kinds,
    );
    expect(again.single.chinese?.file.path, eng.path);
    expect(again.single.foreign?.file.path, chs.path);
  });

  test('applyOverrides can force bilingual kind', () async {
    final root = await Directory.systemTemp.createTemp('manual-bi-');
    addTearDown(() => root.delete(recursive: true));
    final mono = File(p.join(root.path, 'Show.S01E01.chs.srt'));
    await mono.writeAsString('1\n00:00:01,000 --> 00:00:02,000\n你好\n');

    final groups = await FileMatcher.scanFiles([mono]);
    final kinds = {
      ManualGroupEdit.pathKey(mono.path): GroupKind.bilingualFile,
    };
    ManualGroupEdit.applyOverrides(
      groups,
      rolesByPath: const {},
      kindByPath: kinds,
    );

    expect(groups.single.kind, GroupKind.bilingualFile);
    expect(groups.single.bilingualSource?.path, mono.path);
  });
}

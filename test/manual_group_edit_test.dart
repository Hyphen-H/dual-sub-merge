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

  test('applyOverrides restores roles after rescan keys', () async {
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
    ManualGroupEdit.applyOverrides(groups, rolesByPath: roles);

    expect(groups.single.kind, GroupKind.pair);
    expect(groups.single.chinese?.file.path, eng.path);
    expect(groups.single.foreign?.file.path, chs.path);
    expect(groups.single.status, GroupStatus.ready);

    final again = await FileMatcher.scanFiles([chs, eng]);
    ManualGroupEdit.applyOverrides(again, rolesByPath: roles);
    expect(again.single.chinese?.file.path, eng.path);
    expect(again.single.foreign?.file.path, chs.path);
  });
}

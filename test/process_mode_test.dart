import 'dart:io';

import 'package:dual_sub_merge/models/match_group.dart';
import 'package:dual_sub_merge/models/process_mode.dart';
import 'package:dual_sub_merge/models/track_role.dart';
import 'package:dual_sub_merge/services/process_mode_service.dart';
import 'package:flutter_test/flutter_test.dart';

MatchGroup _pair() => MatchGroup(
  prefix: 'show',
  displayPrefix: 'Show',
  chinese: SubtitleFileRef(
    file: File(r'C:\tmp\Show.chs.srt'),
    role: TrackRole.chinese,
  ),
  foreign: SubtitleFileRef(
    file: File(r'C:\tmp\Show.eng.srt'),
    role: TrackRole.foreign,
    languageTag: 'eng',
  ),
  kind: GroupKind.pair,
  status: GroupStatus.ready,
);

MatchGroup _jpPair({bool tagFromContent = false}) => MatchGroup(
  prefix: 'anime',
  displayPrefix: 'Anime',
  chinese: SubtitleFileRef(
    file: File(r'C:\tmp\Anime.chs.srt'),
    role: TrackRole.chinese,
  ),
  foreign: SubtitleFileRef(
    file: File(tagFromContent ? r'C:\tmp\Anime.srt' : r'C:\tmp\Anime.jpn.srt'),
    role: TrackRole.foreign,
    languageTag: tagFromContent ? 'jpn' : null,
  ),
  foreignTag: tagFromContent ? 'jpn' : null,
  kind: GroupKind.pair,
  status: GroupStatus.ready,
);

MatchGroup _zhOnly() => MatchGroup(
  prefix: 'solo',
  displayPrefix: 'Solo',
  chinese: SubtitleFileRef(
    file: File(r'C:\tmp\Solo.chs.srt'),
    role: TrackRole.chinese,
  ),
  kind: GroupKind.pair,
  status: GroupStatus.missingForeign,
);

MatchGroup _enOnly() => MatchGroup(
  prefix: 'en',
  displayPrefix: 'En',
  foreign: SubtitleFileRef(
    file: File(r'C:\tmp\En.eng.srt'),
    role: TrackRole.foreign,
  ),
  kind: GroupKind.pair,
  status: GroupStatus.missingChinese,
);

MatchGroup _bilingual() => MatchGroup(
  prefix: 'dual',
  displayPrefix: 'Dual',
  bilingualSource: File(r'C:\tmp\Dual.ass'),
  kind: GroupKind.bilingualFile,
  status: GroupStatus.bilingualReady,
);

MatchGroup _videoOnly() => MatchGroup(
  prefix: 'v',
  displayPrefix: 'V',
  video: File(r'C:\tmp\V.mkv'),
  kind: GroupKind.videoOnly,
  status: GroupStatus.conflict,
);

void main() {
  test('merge mode keeps scan-time status untouched', () {
    final zh = _zhOnly();
    ProcessModeService.apply([zh], ProcessMode.merge);
    expect(zh.status, GroupStatus.missingForeign);
  });

  test('chineseConvert makes a lone chinese group ready', () {
    final zh = _zhOnly();
    ProcessModeService.apply([zh], ProcessMode.chineseConvert);
    expect(zh.status, GroupStatus.ready);
    expect(zh.statusOk, isTrue);
    expect(zh.message, contains('中下HDRipad'));
  });

  test('chineseConvert flags a foreign-only group as needing check', () {
    final en = _enOnly();
    ProcessModeService.apply([en], ProcessMode.chineseConvert);
    expect(en.statusOk, isFalse);
    expect(en.message, contains('未找到中文'));
    expect(ProcessModeService.isReady(en, ProcessMode.chineseConvert), isFalse);
  });

  test('chineseConvert drops the foreign half of a pair', () {
    final pair = _pair();
    ProcessModeService.apply([pair], ProcessMode.chineseConvert);
    expect(pair.status, GroupStatus.ready);
    expect(
      ProcessModeService.resolveSource(pair)!.path,
      endsWith('Show.chs.srt'),
    );
  });

  test('styleConvert marks bilingual groups convertible', () {
    final bi = _bilingual();
    ProcessModeService.apply([bi], ProcessMode.styleConvert);
    expect(bi.status, GroupStatus.bilingualReady);
    expect(ProcessModeService.isReady(bi, ProcessMode.styleConvert), isTrue);
    expect(ProcessModeService.resolveSource(bi)!.path, endsWith('Dual.ass'));
  });

  test(
    'styleConvert uses the chinese file when no bilingual source exists',
    () {
      final pair = _pair();
      ProcessModeService.apply([pair], ProcessMode.styleConvert);
      expect(pair.status, GroupStatus.bilingualReady);
      expect(
        ProcessModeService.resolveSource(pair)!.path,
        endsWith('Show.chs.srt'),
      );
    },
  );

  test('video-only groups are left alone in every mode', () {
    for (final mode in ProcessMode.values) {
      final v = _videoOnly();
      ProcessModeService.apply([v], mode);
      expect(v.status, GroupStatus.conflict);
      expect(ProcessModeService.resolveSource(v), isNull);
    }
  });

  test('isReady defers to group state in merge mode', () {
    final zh = _zhOnly();
    expect(ProcessModeService.isReady(zh, ProcessMode.merge), isFalse);
    final pair = _pair();
    expect(ProcessModeService.isReady(pair, ProcessMode.merge), isTrue);
  });

  test('jpMerge marks a Chinese + Japanese pair ready', () {
    final jp = _jpPair();
    ProcessModeService.apply([jp], ProcessMode.jpMerge);
    expect(jp.status, GroupStatus.ready);
    expect(jp.statusOk, isTrue);
    expect(jp.message, contains('中日'));
    expect(ProcessModeService.isReady(jp, ProcessMode.jpMerge), isTrue);
  });

  test('jpMerge accepts a Japanese tag detected from content', () {
    final jp = _jpPair(tagFromContent: true);
    expect(ProcessModeService.isReady(jp, ProcessMode.jpMerge), isTrue);
  });

  test('jpMerge flags an English foreign as not Japanese', () {
    final pair = _pair()..captureBaseStatus();
    ProcessModeService.apply([pair], ProcessMode.jpMerge);
    expect(pair.statusOk, isFalse);
    expect(pair.message, contains('不是日文'));
    expect(ProcessModeService.isReady(pair, ProcessMode.jpMerge), isFalse);

    ProcessModeService.apply([pair], ProcessMode.merge);
    expect(pair.status, GroupStatus.ready);
    expect(pair.statusOk, isTrue);
    expect(ProcessModeService.isReady(pair, ProcessMode.merge), isTrue);
  });

  test('jpMerge flags a Chinese-only group as missing Japanese', () {
    final zh = _zhOnly();
    ProcessModeService.apply([zh], ProcessMode.jpMerge);
    expect(zh.status, GroupStatus.missingForeign);
    expect(zh.message, contains('日文'));
    expect(ProcessModeService.isReady(zh, ProcessMode.jpMerge), isFalse);
  });

  test('jpMerge keeps convertible bilingual files usable', () {
    final bi = _bilingual();
    ProcessModeService.apply([bi], ProcessMode.jpMerge);
    expect(bi.status, GroupStatus.bilingualReady);
    expect(ProcessModeService.isReady(bi, ProcessMode.jpMerge), isTrue);
  });

  test('mode labels round-trip through persistence strings', () {
    for (final mode in ProcessMode.values) {
      expect(ProcessModeInfo.parse(ProcessModeInfo.encode(mode)), mode);
    }
    expect(ProcessModeInfo.parse(null), ProcessMode.merge);
    expect(ProcessModeInfo.parse('nope'), ProcessMode.merge);
  });
}

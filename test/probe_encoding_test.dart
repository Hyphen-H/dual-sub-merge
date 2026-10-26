import 'dart:convert';

import 'package:dual_sub_merge/models/extract_pair_mode.dart';
import 'package:dual_sub_merge/services/extract/ffprobe_tracks.dart';
import 'package:dual_sub_merge/services/extract/mkv_probe.dart';
import 'package:dual_sub_merge/services/extract/track_info.dart';
import 'package:dual_sub_merge/services/extract/track_selector.dart';
import 'package:dual_sub_merge/services/language_from_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mkv probe preserves Chinese track names', () {
    final output = jsonEncode({
      'tracks': [
        {
          'id': 4,
          'type': 'subtitles',
          'codec': 'SubStationAlpha',
          'properties': {
            'codec_id': 'S_TEXT/ASS',
            'language': 'chi',
            'track_name': '简体特效ASS',
            'default_track': true,
          },
        },
      ],
    });

    final tracks = MkvProbe.parse(output);
    expect(tracks.single.title, '简体特效ASS');
    expect(tracks.single.isChinese, isTrue);
    expect(tracks.single.codec, 'S_TEXT/ASS');
    expect(tracks.single.textFileExtension, '.ass');
  });

  test('ffprobe preserves Chinese stream titles', () {
    final output = jsonEncode({
      'streams': [
        {
          'index': 3,
          'codec_type': 'subtitle',
          'codec_name': 'ass',
          'tags': {'language': 'chi', 'title': '简体特效ASS'},
          'disposition': {'default': 1, 'forced': 0},
        },
      ],
    });

    final tracks = FfprobeTracks.parse(output);
    expect(tracks.single.title, '简体特效ASS');
    expect(tracks.single.isChinese, isTrue);
  });

  test('SubStationAlpha codec name uses ass extension', () {
    final track = SubtitleTrackInfo(id: 1, codec: 'SubStationAlpha');

    expect(track.isText, isTrue);
    expect(track.textFileExtension, '.ass');
  });

  test('mkv probe prefers IETF script when language is chi', () {
    final output = jsonEncode({
      'tracks': [
        {
          'id': 3,
          'type': 'subtitles',
          'properties': {
            'codec_id': 'S_TEXT/UTF8',
            'language': 'chi',
            'language_ietf': 'zh-Hant',
            'track_name': '繁體中文',
            'default_track': true,
          },
        },
        {
          'id': 4,
          'type': 'subtitles',
          'properties': {
            'codec_id': 'S_TEXT/UTF8',
            'language': 'chi',
            'language_ietf': 'zh-Hans',
            'track_name': '简体中文',
            'default_track': false,
          },
        },
      ],
    });

    final tracks = MkvProbe.parse(output);
    expect(tracks[0].language, 'zh-Hant');
    expect(tracks[0].isTraditionalChinese, isTrue);
    expect(tracks[1].language, 'zh-Hans');
    expect(tracks[1].isSimplifiedChinese, isTrue);
  });

  test('title 简体 is simplified and 繁體 is traditional', () {
    final simplified = SubtitleTrackInfo(
      id: 1,
      codec: 'S_TEXT/UTF8',
      language: 'chi',
      title: '简体中文',
    );
    final traditional = SubtitleTrackInfo(
      id: 2,
      codec: 'S_TEXT/UTF8',
      language: 'chi',
      title: '繁體中文',
      isDefault: true,
    );
    final unmarked = SubtitleTrackInfo(
      id: 3,
      codec: 'S_TEXT/UTF8',
      language: 'chi',
      title: '中文',
    );

    expect(simplified.isSimplifiedChinese, isTrue);
    expect(simplified.isTraditionalChinese, isFalse);
    expect(traditional.isTraditionalChinese, isTrue);
    expect(traditional.isSimplifiedChinese, isFalse);
    expect(unmarked.isChinese, isTrue);
    expect(unmarked.isSimplifiedChinese, isFalse);
    expect(unmarked.isTraditionalChinese, isFalse);
  });

  test('autoSelect prefers simplified over default traditional', () {
    final selected = TrackSelector.autoSelect([
      SubtitleTrackInfo(
        id: 3,
        codec: 'S_TEXT/UTF8',
        language: 'chi',
        title: '繁體中文',
        isDefault: true,
      ),
      SubtitleTrackInfo(
        id: 4,
        codec: 'S_TEXT/UTF8',
        language: 'chi',
        title: '简体中文',
      ),
      SubtitleTrackInfo(id: 5, codec: 'S_TEXT/UTF8', language: 'eng'),
    ]);

    expect(selected.chinese?.id, 4);
    expect(selected.foreign?.id, 5);
  });

  test('autoSelect falls back to unmarked then traditional', () {
    final unmarkedOnly = TrackSelector.autoSelect([
      SubtitleTrackInfo(
        id: 2,
        codec: 'S_TEXT/UTF8',
        language: 'cht',
        title: '繁體中文',
        isDefault: true,
      ),
      SubtitleTrackInfo(
        id: 3,
        codec: 'S_TEXT/UTF8',
        language: 'chi',
        title: '中文',
      ),
    ]);
    expect(unmarkedOnly.chinese?.id, 3);

    final traditionalOnly = TrackSelector.autoSelect([
      SubtitleTrackInfo(
        id: 2,
        codec: 'S_TEXT/UTF8',
        language: 'cht',
        title: '繁體中文',
      ),
    ]);
    expect(traditionalOnly.chinese?.id, 2);
  });

  test('autoSelect follows the requested extract pair mode', () {
    final tracks = [
      SubtitleTrackInfo(
        id: 1,
        codec: 'S_TEXT/UTF8',
        language: 'chi',
        title: '简体中文',
      ),
      SubtitleTrackInfo(id: 2, codec: 'S_TEXT/UTF8', language: 'eng'),
      SubtitleTrackInfo(
        id: 3,
        codec: 'S_TEXT/UTF8',
        language: 'jpn',
        title: '日本語',
      ),
    ];

    final eng = TrackSelector.autoSelect(tracks, mode: ExtractPairMode.chsEng);
    final jpn = TrackSelector.autoSelect(tracks, mode: ExtractPairMode.chsJpn);

    expect(eng.chinese?.id, 1);
    expect(eng.foreign?.id, 2);
    expect(jpn.chinese?.id, 1);
    expect(jpn.foreign?.id, 3);
    expect(
      TrackSelector.autoSelectedIds(tracks, mode: ExtractPairMode.chsEng),
      {1, 2},
    );
    expect(
      TrackSelector.autoSelectedIds(tracks, mode: ExtractPairMode.chsJpn),
      {1, 3},
    );
  });

  test('normal English and Dubtitle extraction modes stay distinct', () {
    final tracks = [
      SubtitleTrackInfo(
        id: 1,
        codec: 'S_TEXT/UTF8',
        language: 'chi',
        title: 'Simplified',
      ),
      SubtitleTrackInfo(id: 2, codec: 'S_TEXT/UTF8', language: 'eng'),
      SubtitleTrackInfo(
        id: 3,
        codec: 'S_TEXT/UTF8',
        language: 'eng',
        title: 'Dubtitle',
      ),
      SubtitleTrackInfo(
        id: 4,
        codec: 'S_TEXT/UTF8',
        language: 'eng',
        title: 'Dubtitle | SDH',
      ),
    ];

    expect(tracks[2].isDubtitle, isTrue);
    expect(tracks[3].isDubtitle, isTrue);
    final english = TrackSelector.autoSelect(
      tracks,
      mode: ExtractPairMode.chsEng,
    );
    expect(english.chinese?.id, 1);
    expect(english.foreign?.id, 2);
    expect(
      TrackSelector.autoSelectedIds(tracks, mode: ExtractPairMode.chsEng),
      {1, 2},
    );

    final dubtitle = TrackSelector.autoSelect(
      tracks,
      mode: ExtractPairMode.chsEngDub,
    );
    expect(dubtitle.chinese?.id, 1);
    expect(dubtitle.foreign?.id, 3);
    expect(
      TrackSelector.autoSelectedIds(tracks, mode: ExtractPairMode.chsEngDub),
      {1, 3},
    );
    expect(
      TrackSelector.autoSelectedIdsForModes(tracks, {
        ExtractPairMode.chsEng,
        ExtractPairMode.chsEngDub,
      }),
      {1, 2, 3},
    );
    expect(LanguageFromName.foreignOutputTag('eng_dub'), 'eng_dub');
  });

  test('Japanese tracks are detected from language and title', () {
    expect(
      SubtitleTrackInfo(id: 1, codec: 'S_TEXT/UTF8', language: 'ja').isJapanese,
      isTrue,
    );
    expect(
      SubtitleTrackInfo(id: 2, codec: 'S_TEXT/UTF8', title: '日语').isJapanese,
      isTrue,
    );
    expect(
      SubtitleTrackInfo(
        id: 3,
        codec: 'S_TEXT/UTF8',
        language: 'eng',
      ).isJapanese,
      isFalse,
    );
    expect(LanguageFromName.foreignOutputTag('ja'), 'jpn');
  });
}

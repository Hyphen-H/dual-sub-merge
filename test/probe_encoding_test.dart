import 'dart:convert';

import 'package:dual_sub_merge/services/extract/ffprobe_tracks.dart';
import 'package:dual_sub_merge/services/extract/mkv_probe.dart';
import 'package:dual_sub_merge/services/extract/track_info.dart';
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
}

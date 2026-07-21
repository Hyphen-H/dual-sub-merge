import 'dart:convert';
import 'dart:io';

import 'track_info.dart';

class MkvProbe {
  static Future<List<SubtitleTrackInfo>> probe(String mkvmerge, String videoPath) async {
    final result = await Process.run(mkvmerge, ['-J', videoPath]);
    if (result.exitCode != 0) {
      throw Exception('mkvmerge 失败: ${result.stderr}');
    }
    final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    final tracks = (json['tracks'] as List?) ?? [];
    final out = <SubtitleTrackInfo>[];
    for (final t in tracks) {
      final map = t as Map<String, dynamic>;
      if (map['type'] != 'subtitles') continue;
      final props = (map['properties'] as Map?)?.cast<String, dynamic>() ?? {};
      out.add(SubtitleTrackInfo(
        id: map['id'] as int,
        codec: (map['codec'] ?? props['codec_id'] ?? '').toString(),
        language: (props['language'] ?? props['language_ietf'] ?? '').toString(),
        title: (props['track_name'] ?? '').toString(),
        isDefault: props['default_track'] == true,
        isForced: props['forced_track'] == true,
      ));
    }
    return out;
  }
}

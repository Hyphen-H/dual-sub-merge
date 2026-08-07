import 'dart:convert';
import 'dart:io';

import 'track_info.dart';

class FfprobeTracks {
  static Future<List<SubtitleTrackInfo>> probe(
    String ffprobe,
    String videoPath,
  ) async {
    final result = await Process.run(ffprobe, [
      '-v',
      'quiet',
      '-print_format',
      'json',
      '-show_streams',
      videoPath,
    ], stdoutEncoding: utf8);
    if (result.exitCode != 0) {
      throw Exception('ffprobe 失败: ${result.stderr}');
    }
    return parse(result.stdout as String);
  }

  static List<SubtitleTrackInfo> parse(String output) {
    final json = jsonDecode(output) as Map<String, dynamic>;
    final streams = (json['streams'] as List?) ?? [];
    final out = <SubtitleTrackInfo>[];
    var subOrdinal = 0;
    for (final s in streams) {
      final map = s as Map<String, dynamic>;
      if (map['codec_type'] != 'subtitle') continue;
      final tags = (map['tags'] as Map?)?.cast<String, dynamic>() ?? {};
      final disposition =
          (map['disposition'] as Map?)?.cast<String, dynamic>() ?? {};
      out.add(
        SubtitleTrackInfo(
          id: subOrdinal,
          streamIndex: map['index'] as int?,
          codec: (map['codec_name'] ?? map['codec_tag_string'] ?? '')
              .toString(),
          language: (tags['language'] ?? '').toString(),
          title: (tags['title'] ?? '').toString(),
          isDefault: disposition['default'] == 1,
          isForced: disposition['forced'] == 1,
        ),
      );
      subOrdinal++;
    }
    return out;
  }
}

import 'dart:convert';
import 'dart:io';

import 'track_info.dart';

class MkvProbe {
  static Future<List<SubtitleTrackInfo>> probe(
    String mkvmerge,
    String videoPath,
  ) async {
    final result = await Process.run(mkvmerge, [
      '-J',
      videoPath,
    ], stdoutEncoding: utf8);
    if (result.exitCode != 0) {
      throw Exception('mkvmerge 失败: ${result.stderr}');
    }
    return parse(result.stdout as String);
  }

  static List<SubtitleTrackInfo> parse(String output) {
    final json = jsonDecode(output) as Map<String, dynamic>;
    final tracks = (json['tracks'] as List?) ?? [];
    final out = <SubtitleTrackInfo>[];
    for (final t in tracks) {
      final map = t as Map<String, dynamic>;
      if (map['type'] != 'subtitles') continue;
      final props = (map['properties'] as Map?)?.cast<String, dynamic>() ?? {};
      out.add(
        SubtitleTrackInfo(
          id: map['id'] as int,
          codec: (props['codec_id'] ?? map['codec'] ?? '').toString(),
          language: _trackLanguage(props),
          title: (props['track_name'] ?? '').toString(),
          isDefault: props['default_track'] == true,
          isForced: props['forced_track'] == true,
        ),
      );
    }
    return out;
  }

  static String _trackLanguage(Map<String, dynamic> props) {
    final lang = (props['language'] ?? '').toString();
    final ietf = (props['language_ietf'] ?? '').toString();
    final generic = {'', 'chi', 'zho', 'zh', 'und'};
    if (generic.contains(lang.toLowerCase()) && ietf.isNotEmpty) {
      return ietf;
    }
    return lang.isNotEmpty ? lang : ietf;
  }
}

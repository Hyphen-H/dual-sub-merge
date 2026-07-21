import 'dart:io';

import 'package:path/path.dart' as p;

class ToolPaths {
  ToolPaths({
    this.mkvmerge,
    this.mkvextract,
    this.ffmpeg,
    this.ffprobe,
  });

  String? mkvmerge;
  String? mkvextract;
  String? ffmpeg;
  String? ffprobe;

  bool get hasMkv => mkvmerge != null && mkvextract != null;
  bool get hasFfmpeg => ffmpeg != null && ffprobe != null;
}

class ToolResolver {
  static Future<ToolPaths> resolve({
    String mkvToolNixDir = '',
    String ffmpegPath = '',
    String ffprobePath = '',
  }) async {
    final paths = ToolPaths();

    if (mkvToolNixDir.trim().isNotEmpty) {
      final dir = mkvToolNixDir.trim();
      paths.mkvmerge = _existing(p.join(dir, 'mkvmerge.exe')) ??
          _existing(p.join(dir, 'mkvmerge'));
      paths.mkvextract = _existing(p.join(dir, 'mkvextract.exe')) ??
          _existing(p.join(dir, 'mkvextract'));
    }

    paths.mkvmerge ??= await _which(['mkvmerge.exe', 'mkvmerge']);
    paths.mkvextract ??= await _which(['mkvextract.exe', 'mkvextract']);

    // common Windows install
    if (paths.mkvmerge == null && Platform.isWindows) {
      const candidates = [
        r'C:\Program Files\MKVToolNix',
        r'C:\Program Files (x86)\MKVToolNix',
      ];
      for (final c in candidates) {
        final m = _existing(p.join(c, 'mkvmerge.exe'));
        final e = _existing(p.join(c, 'mkvextract.exe'));
        if (m != null && e != null) {
          paths.mkvmerge = m;
          paths.mkvextract = e;
          break;
        }
      }
    }

    if (ffmpegPath.trim().isNotEmpty) {
      paths.ffmpeg = _existing(ffmpegPath.trim());
    }
    if (ffprobePath.trim().isNotEmpty) {
      paths.ffprobe = _existing(ffprobePath.trim());
    }
    paths.ffmpeg ??= await _which(['ffmpeg.exe', 'ffmpeg']);
    paths.ffprobe ??= await _which(['ffprobe.exe', 'ffprobe']);

    // if ffmpeg found, try sibling ffprobe
    if (paths.ffmpeg != null && paths.ffprobe == null) {
      final dir = p.dirname(paths.ffmpeg!);
      paths.ffprobe = _existing(p.join(dir, 'ffprobe.exe')) ??
          _existing(p.join(dir, 'ffprobe'));
    }

    return paths;
  }

  static String? _existing(String path) {
    final f = File(path);
    return f.existsSync() ? f.path : null;
  }

  static Future<String?> _which(List<String> names) async {
    for (final name in names) {
      try {
        final result = await Process.run(
          Platform.isWindows ? 'where' : 'which',
          [name],
          runInShell: true,
        );
        if (result.exitCode == 0) {
          final out = (result.stdout as String).trim().split(RegExp(r'\r?\n')).first;
          if (out.isNotEmpty && File(out).existsSync()) return out;
        }
      } catch (_) {}
    }
    return null;
  }
}

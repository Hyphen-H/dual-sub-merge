import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/merge_options.dart';
import '../tools/tool_resolver.dart';
import 'ffprobe_tracks.dart';
import 'mkv_probe.dart';
import 'track_info.dart';
import 'track_selector.dart';

class ExtractNeed {
  ExtractNeed({required this.needChinese, required this.needForeign});
  final bool needChinese;
  final bool needForeign;
}

class FolderTrackChoice {
  /// When user picks a rule for the whole folder.
  SubtitleTrackInfo? Function(List<SubtitleTrackInfo> tracks)? pickChinese;
  SubtitleTrackInfo? Function(List<SubtitleTrackInfo> tracks)? pickForeign;
}

class ExtractService {
  ExtractService(this.tools, this.options);

  final ToolPaths tools;
  final MergeOptions options;

  /// Callback when auto select fails. Return selected tracks or null to skip.
  Future<SelectedTracks?> Function(
    String videoPath,
    List<SubtitleTrackInfo> tracks,
    ExtractNeed need,
  )?
  onNeedUserPick;

  /// Per-track progress during [extractSelectedTracks]: (trackIndex 1-based, total, track).
  void Function(int trackIndex, int total, SubtitleTrackInfo track)?
  onTrackProgress;

  Future<List<SubtitleTrackInfo>> probeTracks(File video) async {
    final ext = p.extension(video.path).toLowerCase();
    if (ext == '.mkv') {
      if (!tools.hasMkv) {
        throw Exception('未找到 mkvmerge/mkvextract，请在设置中配置 MKVToolNix');
      }
      return MkvProbe.probe(tools.mkvmerge!, video.path);
    }
    if (!tools.hasFfmpeg) {
      throw Exception('未找到 ffmpeg/ffprobe，请安装或在设置中配置');
    }
    return FfprobeTracks.probe(tools.ffprobe!, video.path);
  }

  Future<({List<File> files, String log})> extractSelectedTracks({
    required File video,
    required Iterable<SubtitleTrackInfo> tracks,
  }) async {
    final selected = tracks.toList();
    final logs = <String>['已选择 ${selected.length} 条字幕轨'];
    final files = <File>[];
    if (selected.isEmpty) return (files: files, log: logs.join('\n'));

    final isMkv = p.extension(video.path).toLowerCase() == '.mkv';
    if (isMkv && !tools.hasMkv) {
      throw Exception('未找到 mkvmerge/mkvextract，请在设置中配置 MKVToolNix');
    }
    if (!isMkv && !tools.hasFfmpeg) {
      throw Exception('未找到 ffmpeg/ffprobe，请安装或在设置中配置');
    }

    final outDir = Directory(
      p.join(p.dirname(video.path), options.extractSubdir),
    );
    await outDir.create(recursive: true);
    final base = p.basenameWithoutExtension(video.path);
    final tagCounts = <String, int>{};
    var processedTracks = 0;

    for (final track in selected) {
      if (track.isBitmap) {
        logs.add('图像字幕已跳过: ${track.label}');
        continue;
      }
      processedTracks += 1;
      onTrackProgress?.call(processedTracks, selected.length, track);
      final tag = _outputTag(track);
      final count = (tagCounts[tag] ?? 0) + 1;
      tagCounts[tag] = count;
      final uniqueTag = count == 1 ? tag : '$tag.track${track.id}';
      final file = await _extractOne(
        video: video,
        track: track,
        outPath: p.join(outDir.path, '$base.$uniqueTag.extracted'),
        isMkv: isMkv,
      );
      files.add(file);
      logs.add('抽出: ${p.basename(file.path)} ← ${track.label}');
    }

    return (files: files, log: logs.join('\n'));
  }

  Future<({File? chinese, File? foreign, String log})> extractForVideo({
    required File video,
    required ExtractNeed need,
    FolderTrackChoice? folderChoice,
  }) async {
    final logs = <String>[];
    final isMkv = p.extension(video.path).toLowerCase() == '.mkv';
    final tracks = await probeTracks(video);

    logs.add('发现 ${tracks.length} 条字幕轨');
    var selected = TrackSelector.autoSelect(tracks);

    if (folderChoice?.pickChinese != null) {
      selected.chinese = folderChoice!.pickChinese!(tracks) ?? selected.chinese;
    }
    if (folderChoice?.pickForeign != null) {
      selected.foreign = folderChoice!.pickForeign!(tracks) ?? selected.foreign;
    }

    var needPick = false;
    if (need.needChinese && selected.chinese == null) needPick = true;
    if (need.needForeign && selected.foreign == null) needPick = true;
    // foreign only sdh is ok (autoSelect already did)

    if (needPick && onNeedUserPick != null) {
      final user = await onNeedUserPick!(video.path, tracks, need);
      if (user != null) {
        selected = user;
      }
    }

    final outDir = Directory(
      p.join(p.dirname(video.path), options.extractSubdir),
    );
    await outDir.create(recursive: true);
    final base = p.basenameWithoutExtension(video.path);

    File? zhFile;
    File? enFile;

    if (need.needChinese && selected.chinese != null) {
      if (selected.chinese!.isBitmap) {
        logs.add('中文轨为图像字幕，已跳过: ${selected.chinese!.label}');
      } else {
        zhFile = await _extractOne(
          video: video,
          track: selected.chinese!,
          outPath: p.join(outDir.path, '$base.chs.extracted'),
          isMkv: isMkv,
        );
        logs.add('抽出中文: ${p.basename(zhFile.path)}');
      }
    }

    if (need.needForeign && selected.foreign != null) {
      if (selected.foreign!.isBitmap) {
        logs.add('外文轨为图像字幕，已跳过: ${selected.foreign!.label}');
      } else {
        enFile = await _extractOne(
          video: video,
          track: selected.foreign!,
          outPath: p.join(outDir.path, '$base.eng.extracted'),
          isMkv: isMkv,
        );
        logs.add('抽出外文: ${p.basename(enFile.path)}');
      }
    }

    return (chinese: zhFile, foreign: enFile, log: logs.join('\n'));
  }

  String _outputTag(SubtitleTrackInfo track) {
    if (track.isChinese) return 'chs';
    if (track.isEnglish) return 'eng';
    final language = track.language.trim().toLowerCase();
    if (language.isNotEmpty && language != 'und') {
      final safe = language.replaceAll(RegExp(r'[^a-z0-9-]+'), '-');
      if (safe.isNotEmpty) return safe;
    }
    return 'sub';
  }

  Future<File> _extractOne({
    required File video,
    required SubtitleTrackInfo track,
    required String outPath,
    required bool isMkv,
  }) async {
    final codec = track.codec.toLowerCase();
    String ext;
    if (codec.contains('ass') || codec.contains('ssa')) {
      ext = '.ass';
    } else if (codec.contains('vtt') || codec.contains('webvtt')) {
      ext = '.vtt';
    } else {
      ext = '.srt';
    }
    final target = '$outPath$ext';

    if (isMkv) {
      final result = await Process.run(tools.mkvextract!, [
        'tracks',
        video.path,
        '${track.id}:$target',
      ]);
      if (result.exitCode != 0) {
        throw Exception('mkvextract 失败: ${result.stderr}');
      }
    } else {
      final map = track.streamIndex != null
          ? '0:${track.streamIndex}'
          : '0:s:${track.id}';
      final args = <String>['-y', '-i', video.path, '-map', map];
      if (ext == '.srt') {
        args.addAll(['-c:s', 'srt']);
      } else {
        args.addAll(['-c', 'copy']);
      }
      args.add(target);
      final result = await Process.run(tools.ffmpeg!, args);
      if (result.exitCode != 0) {
        throw Exception('ffmpeg 抽轨失败: ${result.stderr}');
      }
    }
    return File(target);
  }
}

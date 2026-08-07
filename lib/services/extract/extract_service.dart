import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/merge_options.dart';
import '../parse/subtitle_loader.dart';
import '../tools/tool_resolver.dart';
import 'ffprobe_tracks.dart';
import 'extract_progress.dart';
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
  void Function(
    int trackIndex,
    int total,
    SubtitleTrackInfo track,
    double fraction,
  )?
  onExtractionProgress;

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
    final extractable = selected.where((track) => !track.isBitmap).toList();
    final logs = <String>['已选择 ${selected.length} 条字幕轨'];
    for (final track in selected.where((track) => track.isBitmap)) {
      logs.add('图像字幕已跳过: ${track.label}');
    }
    final files = <File>[];
    if (extractable.isEmpty) return (files: files, log: logs.join('\n'));

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
    final duration = isMkv ? null : await _probeDuration(video);
    var processedTracks = 0;

    for (final track in extractable) {
      processedTracks += 1;
      onTrackProgress?.call(processedTracks, extractable.length, track);
      final tag = _outputTag(track);
      final count = (tagCounts[tag] ?? 0) + 1;
      tagCounts[tag] = count;
      final uniqueTag = count == 1 ? tag : '$tag.track${track.id}';
      final file = await _extractOne(
        video: video,
        track: track,
        outPath: p.join(outDir.path, '$base.$uniqueTag.extracted'),
        isMkv: isMkv,
        duration: duration,
        onProgress: (fraction) => onExtractionProgress?.call(
          processedTracks,
          extractable.length,
          track,
          fraction,
        ),
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
    final pending = <({SubtitleTrackInfo track, String role, String outPath})>[
      if (need.needChinese &&
          selected.chinese != null &&
          !selected.chinese!.isBitmap)
        (
          track: selected.chinese!,
          role: '中文',
          outPath: p.join(outDir.path, '$base.chs.extracted'),
        ),
      if (need.needForeign &&
          selected.foreign != null &&
          !selected.foreign!.isBitmap)
        (
          track: selected.foreign!,
          role: '外文',
          outPath: p.join(outDir.path, '$base.eng.extracted'),
        ),
    ];
    final duration = isMkv || pending.isEmpty
        ? null
        : await _probeDuration(video);
    var pendingIndex = 0;

    if (need.needChinese && selected.chinese != null) {
      if (selected.chinese!.isBitmap) {
        logs.add('中文轨为图像字幕，已跳过: ${selected.chinese!.label}');
      } else {
        pendingIndex++;
        onTrackProgress?.call(pendingIndex, pending.length, selected.chinese!);
        zhFile = await _extractOne(
          video: video,
          track: selected.chinese!,
          outPath: p.join(outDir.path, '$base.chs.extracted'),
          isMkv: isMkv,
          duration: duration,
          onProgress: (fraction) => onExtractionProgress?.call(
            pendingIndex,
            pending.length,
            selected.chinese!,
            fraction,
          ),
        );
        logs.add('抽出中文: ${p.basename(zhFile.path)}');
      }
    }

    if (need.needForeign && selected.foreign != null) {
      if (selected.foreign!.isBitmap) {
        logs.add('外文轨为图像字幕，已跳过: ${selected.foreign!.label}');
      } else {
        pendingIndex++;
        onTrackProgress?.call(pendingIndex, pending.length, selected.foreign!);
        enFile = await _extractOne(
          video: video,
          track: selected.foreign!,
          outPath: p.join(outDir.path, '$base.eng.extracted'),
          isMkv: isMkv,
          duration: duration,
          onProgress: (fraction) => onExtractionProgress?.call(
            pendingIndex,
            pending.length,
            selected.foreign!,
            fraction,
          ),
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
    required Duration? duration,
    required void Function(double fraction) onProgress,
  }) async {
    final ext = track.textFileExtension;
    final target = '$outPath$ext';

    if (isMkv) {
      final result = await _runProcess(
        tools.mkvextract!,
        ['tracks', video.path, '${track.id}:$target'],
        onOutput: (output) {
          final fraction = parseMkvextractFraction(output);
          if (fraction != null) onProgress(fraction);
        },
      );
      if (result.exitCode != 0) {
        throw Exception('mkvextract 失败: ${result.stderr}');
      }
    } else {
      final map = track.streamIndex != null
          ? '0:${track.streamIndex}'
          : '0:s:${track.id}';
      final args = <String>[
        '-y',
        '-v',
        'error',
        '-nostats',
        '-i',
        video.path,
        '-map',
        map,
      ];
      if (ext == '.srt') {
        args.addAll(['-c:s', 'srt']);
      } else {
        args.addAll(['-c', 'copy']);
      }
      args.addAll(['-progress', 'pipe:1', target]);
      final result = await _runProcess(
        tools.ffmpeg!,
        args,
        onOutput: (output) {
          final fraction = parseFfmpegFraction(
            output,
            duration ?? Duration.zero,
          );
          if (fraction != null) onProgress(fraction);
        },
      );
      if (result.exitCode != 0) {
        throw Exception('ffmpeg 抽轨失败: ${result.stderr}');
      }
    }
    onProgress(1);
    return SubtitleLoader.repairExtractedExtension(File(target));
  }

  Future<Duration?> _probeDuration(File video) async {
    final result = await Process.run(tools.ffprobe!, [
      '-v',
      'error',
      '-show_entries',
      'format=duration',
      '-of',
      'default=noprint_wrappers=1:nokey=1',
      video.path,
    ]);
    if (result.exitCode != 0) return null;
    final seconds = double.tryParse((result.stdout as String).trim());
    if (seconds == null || seconds <= 0) return null;
    return Duration(microseconds: (seconds * 1000000).round());
  }

  Future<({int exitCode, String stdout, String stderr})> _runProcess(
    String executable,
    List<String> arguments, {
    required void Function(String output) onOutput,
  }) async {
    final process = await Process.start(executable, arguments);
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    var progressOutput = '';

    void handleOutput(String text, StringBuffer destination) {
      destination.write(text);
      progressOutput = '$progressOutput$text';
      if (progressOutput.length > 8192) {
        progressOutput = progressOutput.substring(progressOutput.length - 8192);
      }
      onOutput(progressOutput);
    }

    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .forEach((text) => handleOutput(text, stdoutBuffer));
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .forEach((text) => handleOutput(text, stderrBuffer));
    final exitCode = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);
    return (
      exitCode: exitCode,
      stdout: stdoutBuffer.toString(),
      stderr: stderrBuffer.toString(),
    );
  }
}

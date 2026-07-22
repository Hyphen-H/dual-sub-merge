import 'dart:io';

import 'package:flutter/material.dart';

import 'track_role.dart';

enum GroupStatus {
  ready,
  missingChinese,
  missingForeign,
  conflict,
  bilingualInline,
  bilingualReady,
  skipped,
  done,
  failed,
}

enum GroupKind {
  /// Chinese + foreign separate files.
  pair,
  /// Single file with \\N dual lines to convert.
  bilingualFile,
  /// Only video present.
  videoOnly,
}

class SubtitleFileRef {
  SubtitleFileRef({
    required this.file,
    required this.role,
    this.fromExtract = false,
  });

  final File file;
  TrackRole role;
  final bool fromExtract;
}

class MatchGroup {
  MatchGroup({
    required this.prefix,
    this.displayPrefix,
    this.chinese,
    this.foreign,
    this.video,
    this.bilingualSource,
    this.kind = GroupKind.pair,
    this.status = GroupStatus.conflict,
    this.message = '',
    this.outputPath,
    this.selected = true,
  });

  /// Lowercase match key.
  final String prefix;
  /// Original-casing name for output file.
  String? displayPrefix;
  SubtitleFileRef? chinese;
  SubtitleFileRef? foreign;
  File? video;
  /// Single bilingual subtitle file (kind == bilingualFile).
  File? bilingualSource;
  GroupKind kind;
  GroupStatus status;
  String message;
  String? outputPath;
  /// Whether user wants this group processed (default on after scan).
  bool selected;

  String get outputBase =>
      (displayPrefix != null && displayPrefix!.isNotEmpty) ? displayPrefix! : prefix;

  bool get isReady =>
      status == GroupStatus.bilingualReady ||
      (kind == GroupKind.pair &&
          chinese != null &&
          foreign != null &&
          status != GroupStatus.bilingualInline);

  String get kindLabel => switch (kind) {
        GroupKind.pair => '配对',
        GroupKind.bilingualFile => '样式转换',
        GroupKind.videoOnly => '视频',
      };

  IconData get kindIcon => switch (kind) {
        GroupKind.pair => Icons.merge_type,
        GroupKind.bilingualFile => Icons.style,
        GroupKind.videoOnly => Icons.movie_outlined,
      };

  String get kindTooltip => switch (kind) {
        GroupKind.pair =>
          '中外单语字幕按文件名前缀配对，清洗文本后合并为 .chs+eng.ass，并统一 HDRipad 样式。',
        GroupKind.bilingualFile =>
          '将含 \\N 的上下双语拆成中/外双轨，统一 HDRipad 样式写出 .chs+eng.ass（保留源文件）。',
        GroupKind.videoOnly =>
          '从 MKV/MP4 抽取文本字幕轨后再配对合并；跳过 PGS/VobSub 等图像字幕。',
      };
}

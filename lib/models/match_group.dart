import 'dart:io';

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
        GroupKind.bilingualFile => '双语转换',
        GroupKind.videoOnly => '视频',
      };
}

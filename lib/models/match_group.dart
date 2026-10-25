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
    this.languageTag,
  });

  final File file;
  TrackRole role;
  final bool fromExtract;

  /// ISO-ish language tag detected from the filename or content (jpn/eng/…).
  String? languageTag;
}

class MatchGroup {
  MatchGroup({
    required this.prefix,
    this.displayPrefix,
    this.chinese,
    this.foreign,
    this.foreignTag,
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

  /// Language tag of the foreign side, resolved during scanning.
  String? foreignTag;
  File? video;

  /// Single bilingual subtitle file (kind == bilingualFile).
  File? bilingualSource;
  GroupKind kind;
  GroupStatus status;
  String message;
  String? outputPath;

  /// Scan-time readiness, restored when switching back to merge mode.
  GroupStatus? baseStatus;
  String baseMessage = '';

  /// Whether user wants this group processed (default on after scan).
  bool selected;

  void captureBaseStatus() {
    baseStatus = status;
    baseMessage = message;
  }

  String get outputBase => (displayPrefix != null && displayPrefix!.isNotEmpty)
      ? displayPrefix!
      : prefix;

  bool get isReady =>
      status == GroupStatus.bilingualReady ||
      (kind == GroupKind.pair &&
          chinese != null &&
          foreign != null &&
          status != GroupStatus.bilingualInline);

  bool get statusOk => switch (status) {
    GroupStatus.ready || GroupStatus.bilingualReady || GroupStatus.done => true,
    _ => false,
  };

  /// Chinese label for abnormal status; empty when [statusOk].
  String get statusLabelZh => switch (status) {
    GroupStatus.ready || GroupStatus.bilingualReady || GroupStatus.done => '',
    GroupStatus.missingChinese => '缺中文轨',
    GroupStatus.missingForeign => '缺外文轨',
    GroupStatus.conflict => '冲突',
    GroupStatus.bilingualInline => '无法拆分',
    GroupStatus.skipped => '已跳过',
    GroupStatus.failed => '失败',
  };
}

import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/match_group.dart';
import '../models/track_role.dart';
import 'language_from_name.dart';

class LanguageTagRenameResult {
  LanguageTagRenameResult({
    required this.renamedCount,
    required this.skippedCount,
    required this.failCount,
    required this.logs,
  });

  final int renamedCount;
  final int skippedCount;
  final int failCount;
  final List<String> logs;
}

class LanguageTagRenameService {
  static const chsSubdir = 'chs-sub';
  static const engSubdir = 'eng-sub';

  /// Moves subtitle files that lack a trailing language tag into
  /// `chs-sub/` / `eng-sub/` with `.chs` / `.eng` inserted before the extension.
  Future<LanguageTagRenameResult> renameGroups({
    required Directory inputDir,
    required List<MatchGroup> groups,
    bool overwrite = true,
  }) async {
    final logs = <String>[];
    var renamed = 0;
    var skipped = 0;
    var fail = 0;

    for (final g in groups) {
      if (g.kind == GroupKind.bilingualFile) {
        skipped++;
        logs.add('[${g.outputBase}] 跳过双语源（不改名）');
        continue;
      }

      final zh = await _renameRef(
        inputDir: inputDir,
        ref: g.chinese,
        role: TrackRole.chinese,
        overwrite: overwrite,
        groupLabel: g.outputBase,
        logs: logs,
      );
      if (zh != null) g.chinese = zh.$1;
      renamed += zh?.$2 ?? 0;
      skipped += zh?.$3 ?? 0;
      fail += zh?.$4 ?? 0;

      final en = await _renameRef(
        inputDir: inputDir,
        ref: g.foreign,
        role: TrackRole.foreign,
        overwrite: overwrite,
        groupLabel: g.outputBase,
        logs: logs,
      );
      if (en != null) g.foreign = en.$1;
      renamed += en?.$2 ?? 0;
      skipped += en?.$3 ?? 0;
      fail += en?.$4 ?? 0;
    }

    return LanguageTagRenameResult(
      renamedCount: renamed,
      skippedCount: skipped,
      failCount: fail,
      logs: logs,
    );
  }

  /// Returns (updatedRef, renamedDelta, skippedDelta, failDelta) or null if no ref.
  Future<(SubtitleFileRef, int, int, int)?> _renameRef({
    required Directory inputDir,
    required SubtitleFileRef? ref,
    required TrackRole role,
    required bool overwrite,
    required String groupLabel,
    required List<String> logs,
  }) async {
    if (ref == null) return null;
    if (ref.role != role && ref.role != TrackRole.unknown) {
      return (ref, 0, 1, 0);
    }
    if (ref.role == TrackRole.unknown) {
      logs.add('[$groupLabel] 跳过未识别: ${p.basename(ref.file.path)}');
      return (ref, 0, 1, 0);
    }
    if (LanguageFromName.hasTrailingLanguageTag(ref.file.path)) {
      return (ref, 0, 1, 0);
    }

    final tag = role == TrackRole.chinese ? 'chs' : 'eng';
    final sub = role == TrackRole.chinese ? chsSubdir : engSubdir;
    final ext = p.extension(ref.file.path);
    final stem = p.basenameWithoutExtension(ref.file.path);
    final destDir = Directory(p.join(inputDir.path, sub));
    final destPath = p.join(destDir.path, '$stem.$tag$ext');

    try {
      if (!destDir.existsSync()) {
        await destDir.create(recursive: true);
      }
      if (File(destPath).existsSync()) {
        if (!overwrite) {
          logs.add('[$groupLabel] 已存在，跳过: ${p.join(sub, p.basename(destPath))}');
          return (ref, 0, 1, 0);
        }
        await File(destPath).delete();
      }
      final moved = await ref.file.rename(destPath);
      logs.add(
        '[$groupLabel] 改名: ${p.basename(ref.file.path)} → ${p.join(sub, p.basename(moved.path))}',
      );
      return (
        SubtitleFileRef(file: moved, role: role, fromExtract: ref.fromExtract),
        1,
        0,
        0,
      );
    } catch (e) {
      // rename across volumes may fail; fallback to copy+delete
      try {
        if (!destDir.existsSync()) {
          await destDir.create(recursive: true);
        }
        if (File(destPath).existsSync()) {
          if (!overwrite) {
            logs.add('[$groupLabel] 已存在，跳过: ${p.join(sub, p.basename(destPath))}');
            return (ref, 0, 1, 0);
          }
          await File(destPath).delete();
        }
        await ref.file.copy(destPath);
        await ref.file.delete();
        final moved = File(destPath);
        logs.add(
          '[$groupLabel] 改名: ${p.basename(ref.file.path)} → ${p.join(sub, p.basename(moved.path))}',
        );
        return (
          SubtitleFileRef(file: moved, role: role, fromExtract: ref.fromExtract),
          1,
          0,
          0,
        );
      } catch (e2) {
        logs.add('[$groupLabel] 改名失败: ${p.basename(ref.file.path)} — $e2');
        return (ref, 0, 0, 1);
      }
    }
  }
}

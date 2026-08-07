import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/match_group.dart';
import '../models/track_role.dart';
import 'bilingual_inline.dart';
import 'bilingual_split.dart';
import 'language_from_name.dart';
import 'language_tag_rename_service.dart';
import 'parse/subtitle_loader.dart';

class FileMatcher {
  static final _videoExts = {'.mkv', '.mp4'};

  static final _extraSubdirs = {
    LanguageTagRenameService.chsSubdir,
    LanguageTagRenameService.engSubdir,
  };

  static Future<List<MatchGroup>> scanDirectory(
    Directory dir, {
    String extractSubdir = 'dual-sub-merge-extract',
  }) => scanDirectories([dir], extractSubdir: extractSubdir);

  static Future<List<MatchGroup>> scanDirectories(
    Iterable<Directory> dirs, {
    String extractSubdir = 'dual-sub-merge-extract',
  }) async {
    final filesByPath = <String, File>{};
    for (final dir in dirs) {
      for (final file in await listDirectoryFiles(
        dir,
        extractSubdir: extractSubdir,
      )) {
        filesByPath[_pathKey(file.path)] = file;
      }
    }
    return scanFiles(filesByPath.values, extractSubdir: extractSubdir);
  }

  static Future<List<File>> listDirectoryFiles(
    Directory dir, {
    String extractSubdir = 'dual-sub-merge-extract',
  }) async {
    if (!dir.existsSync()) return const [];
    final filesByPath = <String, File>{};
    final entities = await dir.list(recursive: false).toList();
    for (final entity in entities.whereType<File>()) {
      filesByPath[_pathKey(entity.path)] = entity;
    }
    for (final entity in entities.whereType<Directory>()) {
      final name = p.basename(entity.path);
      if (name != extractSubdir && !_extraSubdirs.contains(name)) continue;
      await for (final child in entity.list(recursive: false)) {
        if (child is File) filesByPath[_pathKey(child.path)] = child;
      }
    }
    return filesByPath.values.toList();
  }

  static Future<List<MatchGroup>> scanFiles(
    Iterable<File> files, {
    String extractSubdir = 'dual-sub-merge-extract',
  }) async {
    final subs = <File>[];
    final videos = <File>[];
    final uniqueFiles = <String, File>{
      for (final file in files) _pathKey(file.path): file,
    };
    for (var f in uniqueFiles.values) {
      final ext = p.extension(f.path).toLowerCase();
      if (SubtitleLoader.exts.contains(ext)) {
        f = await SubtitleLoader.repairExtractedExtension(f);
        if (f.path.toLowerCase().endsWith('.chs+eng.ass')) continue;
        subs.add(f);
      } else if (_videoExts.contains(ext)) {
        videos.add(f);
      }
    }

    final map = <String, MatchGroup>{};
    final bilingualCandidates = <File>[];

    for (final f in subs) {
      // Detect bilingual files early
      try {
        final doc = await SubtitleLoader.load(f);
        if (BilingualInlineDetector.isBilingualInline(doc.cues)) {
          final split = BilingualSplit.splitDocument(doc.cues);
          if (split.convertible) {
            bilingualCandidates.add(f);
            continue;
          }
        }
      } catch (_) {}

      final prefix = LanguageFromName.normalizePrefix(f.path);
      final g = map.putIfAbsent(prefix, () => MatchGroup(prefix: prefix));
      g.displayPrefix ??= LanguageFromName.displayPrefix(f.path);
      g.kind = GroupKind.pair;
      var role = LanguageFromName.fromPath(f.path);
      if (role == TrackRole.unknown) {
        try {
          final doc = await SubtitleLoader.load(f);
          role = LanguageFromName.fromContent(doc.cues.map((c) => c.rawText));
        } catch (_) {}
      }
      final ref = SubtitleFileRef(
        file: f,
        role: role,
        fromExtract: f.path.contains(extractSubdir),
      );
      _assign(g, ref);
    }

    // Bilingual single-file groups (unique prefix per file)
    for (final f in bilingualCandidates) {
      final prefix =
          '${LanguageFromName.normalizePrefix(f.path)}::bi::${p.basename(f.path).toLowerCase()}';
      final g = MatchGroup(
        prefix: prefix,
        displayPrefix: LanguageFromName.displayPrefix(f.path),
        bilingualSource: f,
        kind: GroupKind.bilingualFile,
        status: GroupStatus.bilingualReady,
        message: '可转换 \\N 双语',
        selected: true,
      );
      map[prefix] = g;
    }

    for (final v in videos) {
      final prefix = LanguageFromName.normalizePrefix(v.path);
      final existing = map[prefix];
      final key =
          existing?.video != null &&
              _pathKey(existing!.video!.path) != _pathKey(v.path)
          ? '$prefix::video::${_pathKey(v.path)}'
          : prefix;
      final g = map.putIfAbsent(
        key,
        () => MatchGroup(prefix: key, kind: GroupKind.videoOnly),
      );
      g.displayPrefix ??= LanguageFromName.displayPrefix(v.path);
      g.video ??= v;
      if (g.kind != GroupKind.bilingualFile &&
          g.chinese == null &&
          g.foreign == null) {
        g.kind = GroupKind.videoOnly;
      } else if (g.kind != GroupKind.bilingualFile) {
        g.kind = GroupKind.pair;
      }
    }

    for (final g in map.values) {
      if (g.kind == GroupKind.bilingualFile) continue;
      _refreshStatus(g);
    }

    final list = map.values.toList()
      ..sort(
        (a, b) =>
            a.outputBase.toLowerCase().compareTo(b.outputBase.toLowerCase()),
      );
    return list;
  }

  static String _pathKey(String path) =>
      p.normalize(p.absolute(path)).toLowerCase();

  static void _assign(MatchGroup g, SubtitleFileRef ref) {
    if (ref.role == TrackRole.chinese) {
      if (g.chinese == null) {
        g.chinese = ref;
      } else {
        g.message =
            '多个中文字幕: ${p.basename(g.chinese!.file.path)}, ${p.basename(ref.file.path)}';
        g.status = GroupStatus.conflict;
      }
    } else if (ref.role == TrackRole.foreign) {
      if (g.foreign == null) {
        g.foreign = ref;
      } else {
        g.message =
            '多个外文字幕: ${p.basename(g.foreign!.file.path)}, ${p.basename(ref.file.path)}';
        g.status = GroupStatus.conflict;
      }
    } else {
      if (g.chinese == null) {
        g.chinese = ref..role = TrackRole.unknown;
      } else if (g.foreign == null) {
        g.foreign = ref..role = TrackRole.unknown;
      } else {
        g.message = '无法识别语言: ${p.basename(ref.file.path)}';
        g.status = GroupStatus.conflict;
      }
    }
  }

  static void _refreshStatus(MatchGroup g) {
    if (g.status == GroupStatus.conflict && g.message.isNotEmpty) {
      if (g.chinese != null &&
          g.foreign != null &&
          g.chinese!.role != TrackRole.unknown &&
          g.foreign!.role != TrackRole.unknown) {
        // ok
      } else {
        return;
      }
    }

    final hasZh = g.chinese != null && g.chinese!.role == TrackRole.chinese;
    final hasEn = g.foreign != null && g.foreign!.role == TrackRole.foreign;

    if (hasZh && hasEn) {
      g.kind = GroupKind.pair;
      g.status = GroupStatus.ready;
      g.message = '就绪（配对）';
      return;
    }
    if (!hasZh && !hasEn) {
      if (g.video != null) {
        g.kind = GroupKind.videoOnly;
        g.status = GroupStatus.conflict;
        g.message = '缺少字幕（可尝试抽取）';
      } else {
        g.status = GroupStatus.conflict;
        g.message = '缺少中外字幕';
      }
      return;
    }
    if (!hasZh) {
      g.kind = GroupKind.pair;
      g.status = GroupStatus.missingChinese;
      g.message = g.video != null ? '缺中文轨（可抽取）' : '缺中文轨';
      return;
    }
    g.kind = GroupKind.pair;
    g.status = GroupStatus.missingForeign;
    g.message = g.video != null ? '缺外文轨（可抽取）' : '缺外文轨';
  }

  static void reevaluate(MatchGroup g) {
    if (g.kind == GroupKind.bilingualFile) {
      g.status = GroupStatus.bilingualReady;
      g.message = '可转换 \\N 双语';
      return;
    }
    g.message = '';
    g.status = GroupStatus.ready;
    _refreshStatus(g);
  }
}

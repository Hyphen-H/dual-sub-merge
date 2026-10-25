import 'package:path/path.dart' as p;

import '../models/match_group.dart';
import '../models/track_role.dart';
import 'file_matcher.dart';
import 'language_from_name.dart';

/// Manual language role overrides for subtitle groups (session memory by path).
class ManualGroupEdit {
  static String pathKey(String path) =>
      p.normalize(p.absolute(path)).toLowerCase();

  static Iterable<String> subtitlePaths(MatchGroup g) sync* {
    if (g.bilingualSource != null) yield g.bilingualSource!.path;
    if (g.chinese != null) yield g.chinese!.file.path;
    if (g.foreign != null) yield g.foreign!.file.path;
  }

  static void recordRole(
    Map<String, TrackRole> rolesByPath,
    String filePath,
    TrackRole role,
  ) {
    rolesByPath[pathKey(filePath)] = role;
  }

  /// Persist current chinese/foreign roles after a slot rebuild.
  static void syncRolesFromGroup(
    Map<String, TrackRole> rolesByPath,
    MatchGroup g,
  ) {
    if (g.chinese != null) {
      rolesByPath[pathKey(g.chinese!.file.path)] = g.chinese!.role;
    }
    if (g.foreign != null) {
      rolesByPath[pathKey(g.foreign!.file.path)] = g.foreign!.role;
    }
    if (g.bilingualSource != null && g.chinese == null && g.foreign == null) {
      // bilingual source has no track role; leave existing role entry if any
    }
  }

  static bool hasRoleOverride(
    Map<String, TrackRole> rolesByPath,
    String filePath,
  ) => rolesByPath.containsKey(pathKey(filePath));

  /// Set language role of [filePath] inside [g] and rebuild slots.
  static void setFileRole(MatchGroup g, String filePath, TrackRole role) {
    if (g.kind == GroupKind.videoOnly &&
        g.chinese == null &&
        g.foreign == null &&
        g.bilingualSource == null) {
      return;
    }

    if (g.kind == GroupKind.bilingualFile) {
      final src = g.bilingualSource;
      if (src == null) return;
      if (pathKey(src.path) != pathKey(filePath)) return;
      g.kind = GroupKind.pair;
      g.bilingualSource = null;
      g.chinese = null;
      g.foreign = null;
      g.message = '';
      g.status = GroupStatus.ready;
      _placeRef(
        g,
        SubtitleFileRef(
          file: src,
          role: role,
          languageTag: LanguageFromName.explicitOutputFileTag(src.path),
        ),
      );
      FileMatcher.reevaluate(g);
      return;
    }

    final refs = _collectPairRefs(g);
    if (refs.isEmpty) return;
    final key = pathKey(filePath);
    var found = false;
    for (final ref in refs) {
      if (pathKey(ref.file.path) == key) {
        ref.role = role;
        found = true;
      }
    }
    if (!found) return;

    if (role == TrackRole.chinese || role == TrackRole.foreign) {
      final opposite = role == TrackRole.chinese
          ? TrackRole.foreign
          : TrackRole.chinese;
      for (final ref in refs) {
        if (pathKey(ref.file.path) != key && ref.role == role) {
          ref.role = opposite;
        }
      }
    }

    _rebuildPairSlots(g, refs);
    FileMatcher.reevaluate(g);
  }

  /// Re-apply path-keyed role overrides after a rescan.
  static void applyOverrides(
    List<MatchGroup> groups, {
    required Map<String, TrackRole> rolesByPath,
  }) {
    if (rolesByPath.isEmpty) return;

    for (final g in groups) {
      if (g.kind == GroupKind.videoOnly &&
          g.chinese == null &&
          g.foreign == null &&
          g.bilingualSource == null) {
        continue;
      }

      if (g.kind == GroupKind.bilingualFile) {
        final src = g.bilingualSource;
        if (src == null) continue;
        final role = rolesByPath[pathKey(src.path)];
        if (role != null) setFileRole(g, src.path, role);
        continue;
      }

      // pair (or video with subs)
      _applyRolesToPair(g, rolesByPath);
      FileMatcher.reevaluate(g);
    }
  }

  static void _applyRolesToPair(
    MatchGroup g,
    Map<String, TrackRole> rolesByPath,
  ) {
    final refs = _collectPairRefs(g);
    if (refs.isEmpty) return;
    var changed = false;
    for (final ref in refs) {
      final role = rolesByPath[pathKey(ref.file.path)];
      if (role != null && ref.role != role) {
        ref.role = role;
        changed = true;
      }
    }
    if (!changed && rolesByPath.isEmpty) return;

    // Resolve duplicate chinese/foreign after independent overrides
    final zh = refs.where((r) => r.role == TrackRole.chinese).toList();
    final en = refs.where((r) => r.role == TrackRole.foreign).toList();
    if (zh.length > 1) {
      for (var i = 1; i < zh.length; i++) {
        zh[i].role = TrackRole.foreign;
      }
    }
    if (en.length > 1) {
      for (var i = 1; i < en.length; i++) {
        en[i].role = TrackRole.chinese;
      }
    }

    _rebuildPairSlots(g, refs);
  }

  static List<SubtitleFileRef> _collectPairRefs(MatchGroup g) {
    final out = <SubtitleFileRef>[];
    final seen = <String>{};
    void add(SubtitleFileRef? ref) {
      if (ref == null) return;
      final key = pathKey(ref.file.path);
      if (!seen.add(key)) return;
      out.add(
        SubtitleFileRef(
          file: ref.file,
          role: ref.role,
          fromExtract: ref.fromExtract,
          languageTag: ref.languageTag,
        ),
      );
    }

    add(g.chinese);
    add(g.foreign);
    return out;
  }

  static void _rebuildPairSlots(MatchGroup g, List<SubtitleFileRef> refs) {
    g.chinese = null;
    g.foreign = null;
    g.foreignTag = null;
    g.message = '';
    if (g.status == GroupStatus.conflict) {
      g.status = GroupStatus.ready;
    }
    for (final ref in refs) {
      _placeRef(g, ref);
    }
  }

  static void _placeRef(MatchGroup g, SubtitleFileRef ref) {
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
        g.foreignTag = ref.languageTag;
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
        g.foreignTag = ref.languageTag;
      } else {
        g.message = '无法识别语言: ${p.basename(ref.file.path)}';
        g.status = GroupStatus.conflict;
      }
    }
  }
}

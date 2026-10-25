import 'dart:io';

import '../models/match_group.dart';
import '../models/process_mode.dart';
import '../models/track_role.dart';
import 'language_from_name.dart';

/// Recomputes group readiness/labels for the globally selected [ProcessMode].
///
/// The scan-time [GroupStatus] always reflects `ProcessMode.merge`; this service
/// projects it onto the other modes without mutating the group's file slots, so
/// language-role marks made in the list keep working across mode switches.
class ProcessModeService {
  /// Source file a mode will actually read for [g].
  static File? resolveSource(MatchGroup g) {
    if (g.chinese == null && g.foreign == null && g.bilingualSource == null) {
      return null;
    }
    return g.bilingualSource ?? g.chinese?.file ?? g.foreign?.file;
  }

  /// Whether [g] can be processed under [mode].
  static bool isReady(MatchGroup g, ProcessMode mode) {
    switch (mode) {
      case ProcessMode.merge:
        return g.isReady;
      case ProcessMode.jpMerge:
        if (g.kind == GroupKind.bilingualFile) {
          return g.bilingualSource != null;
        }
        return g.chinese != null &&
            g.foreign != null &&
            hasJapaneseForeign(g) &&
            g.status != GroupStatus.bilingualInline;
      case ProcessMode.styleConvert:
      case ProcessMode.chineseConvert:
        return resolveSource(g) != null && !_foreignOnly(g);
    }
  }

  /// True when the foreign slot is a Japanese track (filename token or kana).
  static bool hasJapaneseForeign(MatchGroup g) {
    final ref = g.foreign;
    if (ref == null) return false;
    if (g.foreignTag == 'jpn') return true;
    if (ref.languageTag == 'jpn') return true;
    return LanguageFromName.isJapanesePath(ref.file.path);
  }

  /// Project the global mode onto every subtitle group. Video-only groups are
  /// left untouched; merge mode restores the scan-time status.
  static void apply(List<MatchGroup> groups, ProcessMode mode) {
    if (mode == ProcessMode.merge) {
      for (final g in groups) {
        if (g.baseStatus == null) continue;
        g.status = g.baseStatus!;
        g.message = g.baseMessage;
      }
      return;
    }
    for (final g in groups) {
      if (g.chinese == null && g.foreign == null && g.bilingualSource == null) {
        continue;
      }

      if (g.kind == GroupKind.bilingualFile) {
        g.status = GroupStatus.bilingualReady;
        g.message = mode == ProcessMode.jpMerge ? '可转换中日 \\N 双语' : '可转换 \\N 双语';
        continue;
      }

      if (resolveSource(g) == null) {
        g.status = GroupStatus.conflict;
        g.message = '缺少字幕';
        continue;
      }
      if (_foreignOnly(g)) {
        g.status = GroupStatus.missingChinese;
        g.message = g.video != null ? '未找到中文轨（可手标）' : '未找到中文轨';
        continue;
      }
      if (mode == ProcessMode.jpMerge) {
        if (g.chinese == null) {
          g.status = GroupStatus.missingChinese;
          g.message = g.video != null ? '缺中文轨（可抽取）' : '缺中文轨';
          continue;
        }
        if (g.foreign == null) {
          g.status = GroupStatus.missingForeign;
          g.message = g.video != null ? '缺日文轨（可抽取）' : '缺日文轨';
          continue;
        }
        if (!hasJapaneseForeign(g)) {
          g.status = GroupStatus.missingForeign;
          g.message = '外文不是日文（需日文轨）';
          continue;
        }
        g.status = GroupStatus.ready;
        g.message = '就绪（中日）';
        continue;
      }
      g.status = mode == ProcessMode.styleConvert
          ? GroupStatus.bilingualReady
          : GroupStatus.ready;
      g.message = mode == ProcessMode.styleConvert
          ? '可转换 \\N 双语'
          : '可转换为中下HDRipad';
    }
  }

  /// Chinese source missing: the group's only subtitle is a known foreign track.
  static bool _foreignOnly(MatchGroup g) {
    if (g.bilingualSource != null) return false;
    if (g.chinese != null) return false;
    final foreign = g.foreign;
    return foreign != null && foreign.role == TrackRole.foreign;
  }
}

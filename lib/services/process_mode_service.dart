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
        selectForeignForMode(g, mode);
        return g.isReady;
      case ProcessMode.dubMerge:
        selectForeignForMode(g, mode);
        if (g.kind == GroupKind.bilingualFile) return false;
        return g.chinese != null &&
            g.foreign != null &&
            hasDubtitleForeign(g) &&
            g.status != GroupStatus.bilingualInline;
      case ProcessMode.jpMerge:
        selectForeignForMode(g, mode);
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
    return _foreignCandidates(g).any(_isJapaneseRef);
  }

  /// True when the foreign slot is a Dubtitle track/file.
  static bool hasDubtitleForeign(MatchGroup g) {
    return _foreignCandidates(g).any(_isDubtitleRef);
  }

  static void selectForeignForMode(MatchGroup g, ProcessMode mode) {
    if (!mode.isPairingMode) return;
    final candidates = _foreignCandidates(g);
    if (candidates.isEmpty) return;
    final selected = switch (mode) {
      ProcessMode.dubMerge => candidates.cast<SubtitleFileRef?>().firstWhere(
        (ref) => ref != null && _isDubtitleRef(ref),
        orElse: () => null,
      ),
      ProcessMode.jpMerge => candidates.cast<SubtitleFileRef?>().firstWhere(
        (ref) => ref != null && _isJapaneseRef(ref),
        orElse: () => null,
      ),
      ProcessMode.merge => candidates.cast<SubtitleFileRef?>().firstWhere(
        (ref) => ref != null && !_isDubtitleRef(ref),
        orElse: () => candidates.first,
      ),
      ProcessMode.styleConvert || ProcessMode.chineseConvert => null,
    };
    if (selected != null) {
      g.foreign = selected;
      g.foreignTag = selected.languageTag;
    }
  }

  static List<SubtitleFileRef> _foreignCandidates(MatchGroup g) {
    if (g.foreignCandidates.isNotEmpty) return g.foreignCandidates;
    return [if (g.foreign != null) g.foreign!];
  }

  static bool _isJapaneseRef(SubtitleFileRef ref) {
    return ref.languageTag == 'jpn' ||
        LanguageFromName.isJapanesePath(ref.file.path);
  }

  static bool _isDubtitleRef(SubtitleFileRef ref) {
    return ref.languageTag == 'eng_dub' ||
        LanguageFromName.explicitOutputFileTag(ref.file.path) == 'eng_dub';
  }

  /// Project the global mode onto every subtitle group. Video-only groups are
  /// left untouched; merge mode restores the scan-time status.
  static void apply(List<MatchGroup> groups, ProcessMode mode) {
    for (final g in groups) {
      selectForeignForMode(g, mode);
    }
    if (mode == ProcessMode.merge) {
      for (final g in groups) {
        if (g.baseStatus == null) continue;
        if (g.foreignCandidates.length > 1 &&
            g.chinese != null &&
            g.foreign != null) {
          g.status = GroupStatus.ready;
          g.message = '就绪（配对）';
        } else {
          g.status = g.baseStatus!;
          g.message = g.baseMessage;
        }
      }
      return;
    }
    for (final g in groups) {
      if (g.chinese == null && g.foreign == null && g.bilingualSource == null) {
        continue;
      }

      if (g.kind == GroupKind.bilingualFile) {
        if (mode == ProcessMode.dubMerge) {
          g.status = GroupStatus.conflict;
          g.message = '中英配需要中文 + Dubtitle 字幕';
          continue;
        }
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
      if (mode == ProcessMode.dubMerge) {
        if (g.chinese == null) {
          g.status = GroupStatus.missingChinese;
          g.message = '缺中文轨';
          continue;
        }
        if (g.foreign == null) {
          g.status = GroupStatus.missingForeign;
          g.message = '缺 Dubtitle 轨';
          continue;
        }
        if (!hasDubtitleForeign(g)) {
          g.status = GroupStatus.missingForeign;
          g.message = '外文不是 Dubtitle（需 Dubtitle 轨）';
          continue;
        }
        g.status = GroupStatus.ready;
        g.message = '就绪（中英配）';
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

  static void applySelected(
    List<MatchGroup> groups,
    Iterable<ProcessMode> modes,
  ) {
    final selected = modes.where((mode) => mode.isPairingMode).toList();
    if (selected.length <= 1) {
      apply(groups, selected.isEmpty ? ProcessMode.merge : selected.first);
      return;
    }

    for (final g in groups) {
      if (g.chinese == null && g.foreign == null && g.bilingualSource == null) {
        continue;
      }
      final readyModes = selected.where((mode) => isReady(g, mode)).toList();
      if (readyModes.isNotEmpty) {
        g.status = GroupStatus.ready;
        g.message = '可处理（${readyModes.map((m) => m.label).join(' / ')}）';
      } else {
        g.status = GroupStatus.conflict;
        g.message = '缺少所需字幕组合';
      }
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

import '../../models/extract_pair_mode.dart';
import 'track_info.dart';

class SelectedTracks {
  SelectedTracks({this.chinese, this.foreign});
  SubtitleTrackInfo? chinese;
  SubtitleTrackInfo? foreign;
}

class TrackSelector {
  /// Auto pick Chinese plus the foreign track requested by [mode].
  static SelectedTracks autoSelect(
    List<SubtitleTrackInfo> tracks, {
    ExtractPairMode mode = ExtractPairMode.chsEng,
  }) {
    final text = tracks.where((t) => !t.isBitmap && !t.isCommentary).toList();
    final chinese =
        _best(text.where((t) => t.isSimplifiedChinese).toList()) ??
        _best(
          text
              .where(
                (t) =>
                    t.isChinese &&
                    !t.isSimplifiedChinese &&
                    !t.isTraditionalChinese,
              )
              .toList(),
        ) ??
        _best(text.where((t) => t.isTraditionalChinese).toList());
    final foreign = _pickForeign(text, mode);
    return SelectedTracks(chinese: chinese, foreign: foreign);
  }

  static Set<int> autoSelectedIds(
    List<SubtitleTrackInfo> tracks, {
    ExtractPairMode mode = ExtractPairMode.chsEng,
  }) {
    final selected = autoSelect(tracks, mode: mode);
    return {
      for (final track in [selected.chinese, selected.foreign])
        if (track != null && !track.isBitmap) track.id,
    };
  }

  static SubtitleTrackInfo? _pickForeign(
    List<SubtitleTrackInfo> text,
    ExtractPairMode mode,
  ) {
    final target = switch (mode) {
      ExtractPairMode.chsEng =>
        _best(text.where((t) => t.isEnglish && !t.isSdh).toList()) ??
            _best(text.where((t) => t.isEnglish).toList()) ??
            _best(text.where((t) => t.isSdh && !t.isChinese).toList()),
      ExtractPairMode.chsJpn =>
        _best(text.where((t) => t.isJapanese && !t.isSdh).toList()) ??
            _best(text.where((t) => t.isJapanese).toList()),
    };
    // Keep extraction useful when the requested language is absent.
    return target ?? _best(text.where((t) => !t.isChinese).toList());
  }

  static SubtitleTrackInfo? _best(List<SubtitleTrackInfo> list) {
    if (list.isEmpty) return null;
    list = [...list]
      ..sort((a, b) {
        // prefer non-forced dialogue
        final af = a.isForced ? 1 : 0;
        final bf = b.isForced ? 1 : 0;
        if (af != bf) return af.compareTo(bf);
        final ad = a.isDefault ? 0 : 1;
        final bd = b.isDefault ? 0 : 1;
        return ad.compareTo(bd);
      });
    return list.first;
  }
}

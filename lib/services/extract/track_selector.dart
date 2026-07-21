import 'track_info.dart';

class SelectedTracks {
  SelectedTracks({this.chinese, this.foreign});
  SubtitleTrackInfo? chinese;
  SubtitleTrackInfo? foreign;
}

class TrackSelector {
  /// Auto pick chs + eng (fallback sdh for foreign).
  static SelectedTracks autoSelect(List<SubtitleTrackInfo> tracks) {
    final text = tracks.where((t) => !t.isBitmap && !t.isCommentary).toList();
    final chinese = _best(text.where((t) => t.isChinese).toList());
    var foreign = _best(text.where((t) => t.isEnglish && !t.isSdh).toList());
    foreign ??= _best(text.where((t) => t.isEnglish).toList());
    foreign ??= _best(text.where((t) => t.isSdh).toList());
    // if still null, try non-chinese text
    foreign ??= _best(text.where((t) => !t.isChinese).toList());
    return SelectedTracks(chinese: chinese, foreign: foreign);
  }

  static SubtitleTrackInfo? _best(List<SubtitleTrackInfo> list) {
    if (list.isEmpty) return null;
    list = [...list]..sort((a, b) {
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

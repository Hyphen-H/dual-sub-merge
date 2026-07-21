import '../../models/ass_style.dart';
import '../../models/subtitle_cue.dart';

class SubtitleDocument {
  SubtitleDocument({
    required this.cues,
    this.styles = const [],
    this.playResX,
    this.playResY,
    this.sourcePath = '',
  });

  final List<SubtitleCue> cues;
  final List<AssStyle> styles;
  final int? playResX;
  final int? playResY;
  final String sourcePath;
}

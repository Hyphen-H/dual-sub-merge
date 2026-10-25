import 'app_workspace.dart';
import 'ass_style.dart';
import 'extract_pair_mode.dart';
import 'process_mode.dart';

class ResolutionPreset {
  const ResolutionPreset(this.label, this.width, this.height);
  final String label;
  final int width;
  final int height;

  String get pixelsLabel => '$width×$height';

  static const list = [
    ResolutionPreset('720p', 1280, 720),
    ResolutionPreset('1080p', 1920, 1080),
    ResolutionPreset('1440p', 2560, 1440),
    ResolutionPreset('4K', 3840, 2160),
  ];
}

enum OutputDirMode {
  /// Write into `{input}/Subtitles/`.
  mergedSubdir,

  /// Write next to the inputs.
  source,
}

class MergeOptions {
  MergeOptions({
    this.playResX = 1920,
    this.playResY = 1080,
    this.styleBaseResY = StyleCatalog.defaultBaseResY,
    this.removeCredits = true,
    this.extractSubdir = 'dual-sub-merge-extract',
    this.overwrite = true,
    this.tagLanguageOnMerge = false,
    this.hdrSubtitle = true,
    this.outputDirMode = OutputDirMode.mergedSubdir,
    this.workspace = AppWorkspace.subtitles,
    this.processMode = ProcessMode.merge,
    this.extractPairMode = ExtractPairMode.chsEng,
    this.mkvToolNixDir = '',
    this.ffmpegPath = '',
    this.ffprobePath = '',
    List<String>? blacklistRules,
    List<String>? styleLines,
  }) : blacklistRules =
           blacklistRules ?? List<String>.from(defaultBlacklistRules),
       styleLines =
           styleLines ?? List<String>.from(StyleCatalog.defaultStyleLines);

  /// Output goes to `{input}/Subtitles/`.
  static const mergedSubdirName = 'Subtitles';

  int playResX;
  int playResY;

  /// Authored PlayResY of the current style lines; geometry is scaled from
  /// this to [playResY] on write.
  int styleBaseResY;
  bool removeCredits;
  String extractSubdir;
  bool overwrite;

  /// Move untagged subs into chs-sub/eng-sub with .chs/.eng before merge.
  bool tagLanguageOnMerge;

  /// Emit HDRipad styles; when false the SDR variants are derived instead.
  bool hdrSubtitle;
  OutputDirMode outputDirMode;

  /// Active sidebar workspace.
  AppWorkspace workspace;

  /// Subtitle processing mode used inside the subtitle workspace.
  ProcessMode processMode;

  /// Default language pair used when probing video subtitle tracks.
  ExtractPairMode extractPairMode;
  String mkvToolNixDir;
  String ffmpegPath;
  String ffprobePath;
  List<String> blacklistRules;
  List<String> styleLines;

  static const defaultBlacklistRules = [
    r'^\s*翻译\s*[:：]\s*\S.*$',
    r'^\s*校对\s*[:：]\s*\S.*$',
    r'^\s*调轴\s*[:：]\s*\S.*$',
    r'^\s*时间轴\s*[:：]\s*\S.*$',
    r'^\s*字幕\s*[:：]\s*\S.*$',
    r'^\s*(翻译|校对|调轴|时间轴|压制|特效|监制)\s*[:：]\s*.+$',
    r'^\s*[-—]{0,3}\s*(字幕组|字幕by|subbed\s*by).*$',
    r'^\s*本'
        r'字幕'
        r'仅供爱好者交流[，,]\s*严禁用于任何商业途径\s*$',
  ];
}

import 'ass_style.dart';

class ResolutionPreset {
  const ResolutionPreset(this.label, this.width, this.height);
  final String label;
  final int width;
  final int height;

  static const list = [
    ResolutionPreset('720p', 1280, 720),
    ResolutionPreset('1080p', 1920, 1080),
    ResolutionPreset('1440p', 2560, 1440),
    ResolutionPreset('4K', 3840, 2160),
  ];
}

enum OutputDirMode {
  source,
  mergedSubdir,
  custom,
}

class MergeOptions {
  MergeOptions({
    this.playResX = 1920,
    this.playResY = 1080,
    this.removeCredits = true,
    this.extractFromVideo = true,
    this.extractSubdir = 'dual-sub-merge-extract',
    this.overwrite = true,
    this.dragAutoRun = false,
    this.tagLanguageOnMerge = false,
    this.outputDirMode = OutputDirMode.mergedSubdir,
    this.customOutputDir = '',
    this.mkvToolNixDir = '',
    this.ffmpegPath = '',
    this.ffprobePath = '',
    List<String>? blacklistRules,
    List<String>? styleLines,
  })  : blacklistRules = blacklistRules ?? List<String>.from(defaultBlacklistRules),
        styleLines = styleLines ?? List<String>.from(StyleCatalog.defaultStyleLines);

  static const mergedSubdirName = 'dual-sub-merged';

  int playResX;
  int playResY;
  bool removeCredits;
  bool extractFromVideo;
  String extractSubdir;
  bool overwrite;
  /// After drag-drop scan, automatically start processing.
  bool dragAutoRun;
  /// Move untagged subs into chs-sub/eng-sub with .chs/.eng before merge.
  bool tagLanguageOnMerge;
  OutputDirMode outputDirMode;
  String customOutputDir;
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
    r'^\s*本' r'字幕' r'仅供爱好者交流[，,]\s*严禁用于任何商业途径\s*$',
  ];
}

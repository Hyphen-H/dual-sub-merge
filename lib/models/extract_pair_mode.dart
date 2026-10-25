enum ExtractPairMode { chsEng, chsJpn }

extension ExtractPairModeInfo on ExtractPairMode {
  String get label => switch (this) {
    ExtractPairMode.chsEng => '中英',
    ExtractPairMode.chsJpn => '中日',
  };

  String get tooltip => switch (this) {
    ExtractPairMode.chsEng => '默认勾选中文 + 英文轨，展开视频后可逐轨调整',
    ExtractPairMode.chsJpn => '默认勾选中文 + 日文轨，展开视频后可逐轨调整',
  };

  static ExtractPairMode parse(String? raw) {
    return raw == 'chsJpn' || raw == 'jpn'
        ? ExtractPairMode.chsJpn
        : ExtractPairMode.chsEng;
  }

  static String encode(ExtractPairMode mode) => mode.name;
}

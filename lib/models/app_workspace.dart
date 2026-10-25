enum AppWorkspace { subtitles, extract }

extension AppWorkspaceInfo on AppWorkspace {
  static AppWorkspace parse(String? raw) {
    return raw == 'extract' ? AppWorkspace.extract : AppWorkspace.subtitles;
  }

  static String encode(AppWorkspace workspace) => workspace.name;
}

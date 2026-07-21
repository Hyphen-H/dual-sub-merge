enum TrackRole {
  chinese,
  foreign,
  unknown,
}

extension TrackRoleX on TrackRole {
  String get label => switch (this) {
        TrackRole.chinese => '中文',
        TrackRole.foreign => '外文',
        TrackRole.unknown => '未知',
      };
}

class TrainerInviteQr {
  const TrainerInviteQr._(this.version, this.token);

  final int version;
  final String token;

  /// Validates the invite format only, not server validity or expiry.
  static TrainerInviteQr? parse(String raw) {
    if (raw.trim() != raw || RegExp(r'%(?![0-9a-fA-F]{2})').hasMatch(raw)) {
      return null;
    }
    try {
      final uri = Uri.tryParse(raw);
      if (uri == null ||
          !const {'setkeep', 'musclemory'}.contains(uri.scheme) ||
          uri.host != 'trainer' ||
          uri.path != '/invite' ||
          uri.userInfo.isNotEmpty ||
          uri.hasPort ||
          uri.hasFragment) {
        return null;
      }
      final query = uri.queryParametersAll;
      if (query.length != 2 ||
          query['v']?.length != 1 ||
          query['v']?.single != '1' ||
          query['token']?.length != 1) {
        return null;
      }
      final token = query['token']!.single;
      if (token.trim().isEmpty) return null;
      return TrainerInviteQr._(1, token);
    } on FormatException {
      return null;
    }
  }
}

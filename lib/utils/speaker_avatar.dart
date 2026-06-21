class SpeakerAvatar {
  static const avatarPaths = [
    'assets/avatars/young_male.png',
    'assets/avatars/young_female.png',
    'assets/avatars/adult_male.png',
    'assets/avatars/adult_female.png',
    'assets/avatars/senior_male.png',
    'assets/avatars/senior_female.png',
    'assets/avatars/manager.png',
    'assets/avatars/chairperson.png',
  ];

  static const _keywordRules = [
    _AvatarKeywordRule(
      ['董事长', '董事', '主席', '总裁', 'ceo', 'chairman'],
      'assets/avatars/chairperson.png',
    ),
    _AvatarKeywordRule(
      ['经理', '主管', '负责人', 'manager', 'lead'],
      'assets/avatars/manager.png',
    ),
    _AvatarKeywordRule(
      ['女士', '小姐', '女', 'female'],
      'assets/avatars/adult_female.png',
    ),
    _AvatarKeywordRule(
      ['先生', '男', 'male'],
      'assets/avatars/adult_male.png',
    ),
    _AvatarKeywordRule(
      ['老', '资深', 'senior'],
      'assets/avatars/senior_male.png',
    ),
  ];

  static String assetFor({
    required String speakerId,
    required String displayName,
  }) {
    final normalized = displayName.trim().toLowerCase();
    for (final rule in _keywordRules) {
      if (rule.keywords.any(normalized.contains)) {
        return rule.assetPath;
      }
    }
    return avatarPaths[_stableIndex(speakerId, avatarPaths.length)];
  }

  static int _stableIndex(String value, int length) {
    var hash = 0;
    for (final unit in value.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash % length;
  }
}

class _AvatarKeywordRule {
  const _AvatarKeywordRule(this.keywords, this.assetPath);
  final List<String> keywords;
  final String assetPath;
}

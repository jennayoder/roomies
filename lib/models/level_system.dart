import 'package:flutter/material.dart';

/// Metadata for a single level.
class LevelInfo {
  final int level;
  final int xpRequired;
  final String title;
  final String emoji;
  final String avatarEmoji;
  final Color themeColor;

  const LevelInfo({
    required this.level,
    required this.xpRequired,
    required this.title,
    required this.emoji,
    required this.avatarEmoji,
    required this.themeColor,
  });
}

/// Static XP / level ladder and helpers.
class LevelSystem {
  static const List<LevelInfo> levels = [
    LevelInfo(level: 1, xpRequired: 0,    title: 'Couch Surfer',    emoji: '🛋️', avatarEmoji: '🛋️', themeColor: Color(0xFF9E9E9E)),
    LevelInfo(level: 2, xpRequired: 200,  title: 'Roomie',          emoji: '🔑', avatarEmoji: '🔑', themeColor: Color(0xFF6750A4)),
    LevelInfo(level: 3, xpRequired: 500,  title: 'Reliable Roomie', emoji: '✅', avatarEmoji: '✅', themeColor: Color(0xFF00897B)),
    LevelInfo(level: 4, xpRequired: 1000, title: 'Household Hero',  emoji: '🦸', avatarEmoji: '🦸', themeColor: Color(0xFF1565C0)),
    LevelInfo(level: 5, xpRequired: 2000, title: 'House Champion',  emoji: '👑', avatarEmoji: '👑', themeColor: Color(0xFFF57F17)),
    LevelInfo(level: 6, xpRequired: 3500, title: 'Legend',          emoji: '🌟', avatarEmoji: '🌟', themeColor: Color(0xFFAD1457)),
    LevelInfo(level: 7, xpRequired: 5000, title: 'Hall of Fame',    emoji: '🏆', avatarEmoji: '🏆', themeColor: Color(0xFFBF360C)),
  ];

  static int get maxLevel => levels.last.level;

  static LevelInfo infoFor(int level) =>
      levels[(level.clamp(1, maxLevel) - 1)];

  /// Calculates which level a given [xp] amount corresponds to.
  static int fromXp(int xp) {
    int result = 1;
    for (final info in levels) {
      if (xp >= info.xpRequired) {
        result = info.level;
      } else {
        break;
      }
    }
    return result;
  }

  static int xpForLevel(int level) => infoFor(level).xpRequired;

  static int? xpForNextLevel(int level) {
    if (level >= maxLevel) return null;
    return infoFor(level + 1).xpRequired;
  }

  /// [0.0, 1.0] fraction of the way through the current level band.
  static double progressToNextLevel(int totalXp, int currentLevel) {
    if (currentLevel >= maxLevel) return 1.0;
    final current = xpForLevel(currentLevel);
    final next = xpForNextLevel(currentLevel)!;
    return ((totalXp - current) / (next - current)).clamp(0.0, 1.0);
  }

  /// XP still needed to reach the next level (0 if at max).
  static int xpNeededForNext(int totalXp, int currentLevel) {
    if (currentLevel >= maxLevel) return 0;
    return xpForNextLevel(currentLevel)! - totalXp;
  }

  /// Returns all avatar emojis unlocked through [level].
  static List<String> avatarsUnlockedAt(int level) =>
      levels.where((l) => l.level <= level).map((l) => l.avatarEmoji).toList();

  /// Returns all theme colors unlocked through [level].
  static List<Color> themesUnlockedAt(int level) =>
      levels.where((l) => l.level <= level).map((l) => l.themeColor).toList();

  static String colorToHex(Color c) =>
      '#${(c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  static Color hexToColor(String hex) {
    final clean = hex.replaceAll('#', '');
    return Color(int.parse('FF$clean', radix: 16));
  }
}

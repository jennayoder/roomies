import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/level_system.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/theme_notifier.dart';
import '../../services/xp_service.dart';
import '../../widgets/loading_widget.dart';
import '../leaderboard/leaderboard_screen.dart';

/// Profile tab — shows avatar, XP progress, trophy case, and pickers for
/// avatar and theme color.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final uid = auth.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<UserModel?>(
      stream: auth.userProfileStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: LoadingWidget(message: 'Loading profile…'),
          );
        }
        return _ProfileContent(user: snapshot.data!, uid: uid);
      },
    );
  }
}

class _ProfileContent extends StatelessWidget {
  final UserModel user;
  final String uid;

  const _ProfileContent({required this.user, required this.uid});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final levelInfo = LevelSystem.infoFor(user.level);
    final progress = LevelSystem.progressToNextLevel(user.totalXp, user.level);
    final xpNeeded = LevelSystem.xpNeededForNext(user.totalXp, user.level);
    final nextLevel =
        user.level < LevelSystem.maxLevel ? LevelSystem.infoFor(user.level + 1) : null;

    final avatarEmoji = user.currentAvatar ?? levelInfo.avatarEmoji;

    // Fall back to defaults for users who haven't unlocked anything yet.
    final unlockedAvatars = user.unlockedAvatars.isNotEmpty
        ? user.unlockedAvatars
        : LevelSystem.avatarsUnlockedAt(user.level);
    final unlockedThemes = user.unlockedThemes.isNotEmpty
        ? user.unlockedThemes
        : LevelSystem.themesUnlockedAt(user.level).map(LevelSystem.colorToHex).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // ── Avatar + Name + Title ────────────────────────────────────────────
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundColor: colors.primaryContainer,
                  child: Text(
                    avatarEmoji,
                    style: const TextStyle(fontSize: 42),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      user.displayName,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: Icon(Icons.edit_outlined,
                          size: 18, color: colors.onSurfaceVariant),
                      tooltip: 'Edit name',
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          _showEditNameDialog(context, uid, user.displayName),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Chip(
                  label: Text(
                    '${levelInfo.emoji}  ${user.title ?? levelInfo.title}',
                    style: TextStyle(color: colors.onSecondaryContainer),
                  ),
                  backgroundColor: colors.secondaryContainer,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── XP Progress Card ─────────────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Level ${user.level} — ${levelInfo.title}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${user.totalXp} XP',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _AnimatedXpBar(progress: progress),
                  const SizedBox(height: 8),
                  nextLevel != null
                      ? Text(
                          '$xpNeeded XP to ${nextLevel.title}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                        )
                      : Text(
                          'Max level reached! 🏆',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Leaderboard shortcut ─────────────────────────────────────────────
          Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LeaderboardScreen()),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(Icons.emoji_events,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'View Leaderboard',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Trophy Case ──────────────────────────────────────────────────────
          Text('Trophy Case', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 20,
                runSpacing: 12,
                children: LevelSystem.levels.map((lvl) {
                  final earned = user.level >= lvl.level;
                  return Opacity(
                    opacity: earned ? 1.0 : 0.25,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(lvl.emoji, style: const TextStyle(fontSize: 30)),
                        const SizedBox(height: 4),
                        Text(
                          lvl.title,
                          style: Theme.of(context).textTheme.labelSmall,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Avatar Selector ──────────────────────────────────────────────────
          Text('Avatar', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: unlockedAvatars.map((emoji) {
                  final selected = avatarEmoji == emoji;
                  return GestureDetector(
                    onTap: () => XpService().setAvatar(uid, emoji),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected
                            ? colors.primaryContainer
                            : colors.surfaceContainerHighest,
                        border: selected
                            ? Border.all(color: colors.primary, width: 2.5)
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(emoji, style: const TextStyle(fontSize: 28)),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Theme Color Selector ─────────────────────────────────────────────
          Text('Theme Color', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: unlockedThemes.map((hex) {
                  final color = LevelSystem.hexToColor(hex);
                  final isSelected = (user.currentTheme == hex) ||
                      (user.currentTheme == null &&
                          hex == LevelSystem.colorToHex(LevelSystem.infoFor(1).themeColor));
                  return GestureDetector(
                    onTap: () {
                      XpService().setTheme(uid, hex);
                      context.read<ThemeNotifier>().setSeedColor(color);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                        border: isSelected
                            ? Border.all(
                                color: colors.outline,
                                width: 3,
                              )
                            : Border.all(
                                color: Colors.transparent,
                                width: 3,
                              ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: color.withOpacity(0.5),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                )
                              ]
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Edit display name dialog ─────────────────────────────────────────────────

Future<void> _showEditNameDialog(
  BuildContext context,
  String uid,
  String currentName,
) async {
  final ctrl = TextEditingController(text: currentName);
  final formKey = GlobalKey<FormState>();

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Change display name'),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: ctrl,
          textCapitalization: TextCapitalization.words,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Display name',
            border: OutlineInputBorder(),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Name can\'t be empty';
            if (v.trim().length > 30) return 'Max 30 characters';
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            if (!formKey.currentState!.validate()) return;
            final newName = ctrl.text.trim();
            if (newName == currentName) {
              Navigator.pop(ctx);
              return;
            }
            await FirestoreService().updateDisplayName(uid, newName);
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

// ─── Animated XP progress bar ─────────────────────────────────────────────────

class _AnimatedXpBar extends StatefulWidget {
  final double progress;

  const _AnimatedXpBar({required this.progress});

  @override
  State<_AnimatedXpBar> createState() => _AnimatedXpBarState();
}

class _AnimatedXpBarState extends State<_AnimatedXpBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.animateTo(widget.progress);
  }

  @override
  void didUpdateWidget(_AnimatedXpBar old) {
    super.didUpdateWidget(old);
    if (old.progress != widget.progress) {
      _ctrl.animateTo(widget.progress);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(
          value: _anim.value,
          minHeight: 16,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
      ),
    );
  }
}

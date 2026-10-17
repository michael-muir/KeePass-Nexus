import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.autoLockMinutes,
    required this.onAutoLockChanged,
    super.key,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final int autoLockMinutes;
  final ValueChanged<int> onAutoLockChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        Text('Settings', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Personalize how KeePass Nexus looks and protects your vault.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 26),
        _SettingsCard(
          icon: Icons.palette_outlined,
          title: 'Appearance',
          subtitle: 'Choose how KeePass Nexus looks on this device.',
          child: DropdownButtonFormField<ThemeMode>(
            initialValue: themeMode,
            decoration: const InputDecoration(labelText: 'Theme'),
            items: const [
              DropdownMenuItem(
                  value: ThemeMode.system, child: Text('Use system setting')),
              DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
              DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
            ],
            onChanged: (value) {
              if (value != null) onThemeModeChanged(value);
            },
          ),
        ),
        const SizedBox(height: 16),
        _SettingsCard(
          icon: Icons.lock_clock_outlined,
          title: 'Security',
          subtitle: 'Keep your unlocked database protected.',
          child: DropdownButtonFormField<int>(
            initialValue: autoLockMinutes,
            decoration:
                const InputDecoration(labelText: 'Lock after inactivity'),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Never automatically')),
              DropdownMenuItem(value: 1, child: Text('1 minute')),
              DropdownMenuItem(value: 5, child: Text('5 minutes')),
              DropdownMenuItem(value: 15, child: Text('15 minutes')),
              DropdownMenuItem(value: 30, child: Text('30 minutes')),
            ],
            onChanged: (value) {
              if (value != null) onAutoLockChanged(value);
            },
          ),
        ),
        const SizedBox(height: 16),
        _SettingsCard(
          icon: Icons.info_outline,
          title: 'About KeePass Nexus',
          subtitle:
              'Local-first password management with KeePass compatibility.',
          child: Row(
            children: [
              const Expanded(child: Text('Version')),
              Text('0.1.0', style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

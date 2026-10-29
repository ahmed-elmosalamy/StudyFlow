import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const _appVersion = '1.0.0+1';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            key: const ValueKey('settings-availability-tile'),
            leading: const Icon(Icons.calendar_month_outlined),
            title: const Text('Availability'),
            subtitle: const Text('Weekly study windows'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/availability'),
          ),
          ListTile(
            key: const ValueKey('settings-planning-limits-tile'),
            leading: const Icon(Icons.tune),
            title: const Text('Planning Limits'),
            subtitle: const Text('Daily study limit, block length, and breaks'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/planning-limits'),
          ),
          ListTile(
            key: const ValueKey('settings-appearance-tile'),
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Appearance'),
            subtitle: const Text('Theme and color options (coming soon)'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Appearance settings are coming soon.'),
                ),
              );
            },
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'App Information',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Version'),
            subtitle: Text(_appVersion),
          ),
        ],
      ),
    );
  }
}

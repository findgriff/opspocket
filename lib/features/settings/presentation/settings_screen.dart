import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/core/constants/app_constants.dart';
import '../../../app/theme/app_theme.dart';
import '../../../shared/models/provider_credential.dart';
import '../../../shared/models/server_profile.dart';
import '../../audit/data/audit_repository_impl.dart';
import '../../providers/data/provider_credential_repository.dart';
import '../data/settings_repository.dart';

/// Catch-all settings screen. Keeps things flat — one scroll, no nested nav.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Map<String, String> _settings = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await ref.read(settingsRepositoryProvider).all();
    if (mounted) setState(() => _settings = s);
  }

  bool _bool(String key, {bool fallback = false}) {
    final v = _settings[key];
    if (v == null) return fallback;
    return v == 'true';
  }

  int _int(String key, {required int fallback}) => int.tryParse(_settings[key] ?? '') ?? fallback;

  Future<void> _set(String key, String value) async {
    await ref.read(settingsRepositoryProvider).set(key, value);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final providerStream = ref.watch(providerCredentialsStreamProvider(null));

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _sectionHeader('Security'),
          SwitchListTile(
            title: const Text('Biometric lock'),
            subtitle: const Text('Require Face ID / fingerprint / PIN on open'),
            value: _bool(SettingKeys.biometricLock, fallback: false),
            onChanged: (v) => _set(SettingKeys.biometricLock, v.toString()),
          ),
          ListTile(
            title: const Text('App lock timeout'),
            subtitle: Text('${_int(SettingKeys.appLockTimeoutSeconds, fallback: AppConstants.defaultLockTimeout.inSeconds)} seconds'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editInt(
              title: 'App lock timeout (seconds)',
              key: SettingKeys.appLockTimeoutSeconds,
              fallback: AppConstants.defaultLockTimeout.inSeconds,
              min: 10,
              max: 3600,
            ),
          ),
          SwitchListTile(
            title: const Text('Require dangerous-action confirmation'),
            subtitle: const Text('Typed-confirm before rm/reboot/destructive commands'),
            value: _bool(SettingKeys.dangerousConfirmation, fallback: true),
            onChanged: (v) => _set(SettingKeys.dangerousConfirmation, v.toString()),
          ),

          _sectionHeader('Terminal & logs'),
          ListTile(
            title: const Text('Default log line count'),
            subtitle: Text('${_int(SettingKeys.defaultLogLines, fallback: AppConstants.defaultLogLines)}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editInt(
              title: 'Default log line count',
              key: SettingKeys.defaultLogLines,
              fallback: AppConstants.defaultLogLines,
              min: 10,
              max: 5000,
            ),
          ),
          ListTile(
            title: const Text('Terminal font size'),
            subtitle: Text('${_int(SettingKeys.terminalFontSize, fallback: 13)} pt'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editInt(
              title: 'Terminal font size',
              key: SettingKeys.terminalFontSize,
              fallback: 13,
              min: 10,
              max: 20,
            ),
          ),

          _sectionHeader('Cloud providers'),
          providerStream.when(
            loading: () => const ListTile(title: Text('Loading…')),
            error: (e, _) => ListTile(title: Text('Error: $e')),
            data: (creds) {
              return Column(
                children: [
                  for (final c in creds)
                    ListTile(
                      leading: const Icon(Icons.cloud_outlined),
                      title: Text(c.label),
                      subtitle: Text(c.providerType.name),
                      trailing: IconButton(
                        tooltip: 'Remove token',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _removeToken(c),
                      ),
                    ),
                  ListTile(
                    leading: Icon(Icons.add, color: AppTheme.accent),
                    title: Text('Add DigitalOcean token', style: TextStyle(color: AppTheme.accent)),
                    onTap: _addDigitalOceanToken,
                  ),
                ],
              );
            },
          ),

          _sectionHeader('Audit'),
          ListTile(
            leading: Icon(Icons.delete_sweep_outlined, color: AppTheme.danger),
            title: Text('Clear all audit logs', style: TextStyle(color: AppTheme.danger)),
            subtitle: const Text('Local only — not synced anywhere'),
            onTap: _clearAudit,
          ),

          const SizedBox(height: 40),
          const Center(child: Text('OpsPocket  ·  MVP', style: TextStyle(color: Colors.white30))),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionHeader(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 6),
        child: Text(t, style: TextStyle(color: AppTheme.muted, fontSize: 12, fontWeight: FontWeight.w600)),
      );

  Future<void> _editInt({
    required String title,
    required String key,
    required int fallback,
    required int min,
    required int max,
  }) async {
    final controller = TextEditingController(text: _int(key, fallback: fallback).toString());
    final result = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final n = int.tryParse(controller.text.trim());
              if (n == null || n < min || n > max) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Must be $min–$max')),
                );
                return;
              }
              Navigator.of(context).pop(n);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null) {
      await _set(key, result.toString());
    }
  }

  Future<void> _addDigitalOceanToken() async {
    final labelCtl = TextEditingController(text: 'DO main');
    final tokenCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add DigitalOcean token'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelCtl,
              decoration: const InputDecoration(labelText: 'Label'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: tokenCtl,
              decoration: const InputDecoration(labelText: 'dop_v1_…'),
              obscureText: true,
              autocorrect: false,
            ),
            const SizedBox(height: 8),
            Text(
              'Token is stored in the OS keychain, not in the database.',
              style: TextStyle(color: AppTheme.muted, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    if (tokenCtl.text.trim().isEmpty) return;
    final repo = ref.read(providerCredentialRepositoryProvider);
    await repo.create(
      type: ProviderType.digitalOcean,
      label: labelCtl.text.trim(),
      token: tokenCtl.text.trim(),
    );
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Token saved')));
  }

  Future<void> _removeToken(ProviderCredential c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove token?'),
        content: Text('This removes "${c.label}" from this device. The token itself is not revoked on DigitalOcean.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Remove', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(providerCredentialRepositoryProvider).delete(c.id);
  }

  Future<void> _clearAudit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear audit logs?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Clear', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(auditRepositoryProvider).clearAll();
  }
}

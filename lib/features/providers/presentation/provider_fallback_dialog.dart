import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/core/errors/app_error.dart';
import '../../../app/core/widgets/dangerous_confirm_dialog.dart';
import '../../../app/theme/app_theme.dart';
import '../../../shared/models/server_profile.dart';
import '../../audit/data/audit_repository_impl.dart';
import '../../auth_security/data/biometric_gate_impl.dart';
import '../../server_profiles/data/server_profile_repository_impl.dart';
import '../../settings/data/settings_repository.dart';
import '../data/digital_ocean_api.dart';
import '../data/provider_credential_repository.dart';

/// Surfaces DigitalOcean reboot / power-cycle for a server profile, typically
/// when SSH has failed. Refuses to run on a server without a matching
/// provider credential configured.
class ProviderFallbackDialog {
  ProviderFallbackDialog._();

  static Future<void> show({
    required BuildContext context,
    required WidgetRef ref,
    required String serverId,
  }) async {
    final repo = ref.read(serverProfileRepositoryProvider);
    final server = await repo.getById(serverId);
    if (server == null) return;

    if (server.providerType != ProviderType.digitalOcean) {
      if (!context.mounted) return;
      await _showInfo(
        context,
        title: 'No provider configured',
        body: 'This server is not linked to a cloud provider. Add provider details in the edit screen to enable reboot fallback.',
      );
      return;
    }
    if (server.providerResourceId == null || server.providerResourceId!.isEmpty) {
      if (!context.mounted) return;
      await _showInfo(
        context,
        title: 'Missing droplet ID',
        body: 'Edit this server and add its DigitalOcean droplet ID to use provider fallback.',
      );
      return;
    }

    final creds = await ref.read(providerCredentialRepositoryProvider).getAll(
          type: ProviderType.digitalOcean,
        );
    if (creds.isEmpty) {
      if (!context.mounted) return;
      await _showInfo(
        context,
        title: 'No DigitalOcean token',
        body: 'Add a DigitalOcean token in Settings to enable the provider fallback.',
      );
      return;
    }

    // Prefer the credential saved as the default; else first.
    final selectedId = await ref.read(settingsRepositoryProvider).get(SettingKeys.selectedProviderCredentialId);
    final cred = creds.firstWhere(
      (c) => c.id == selectedId,
      orElse: () => creds.first,
    );

    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Theme.of(context).cardColor,
      builder: (_) => _Sheet(
        serverId: serverId,
        resourceId: server.providerResourceId!,
        credentialId: cred.id,
      ),
    );
  }

  static Future<void> _showInfo(BuildContext context, {required String title, required String body}) {
    return showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
      ),
    );
  }
}

class _Sheet extends ConsumerStatefulWidget {
  final String serverId;
  final String resourceId;
  final String credentialId;
  const _Sheet({
    required this.serverId,
    required this.resourceId,
    required this.credentialId,
  });

  @override
  ConsumerState<_Sheet> createState() => _SheetState();
}

class _SheetState extends ConsumerState<_Sheet> {
  bool _busy = false;
  String? _statusLine;

  Future<DigitalOceanApi> _client() async {
    final token = await ref.read(providerCredentialRepositoryProvider).readToken(widget.credentialId);
    if (token == null) {
      throw const ProviderApiError('Token missing from secure storage');
    }
    return DigitalOceanApi(token: token);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_outlined, color: AppTheme.accent),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('DigitalOcean fallback', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Droplet ${widget.resourceId}',
              style: AppTheme.mono(size: 12, color: AppTheme.muted),
            ),
            const SizedBox(height: 16),
            if (_statusLine != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_statusLine!, style: AppTheme.mono(size: 12)),
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: _busy ? null : _fetchStatus,
                    icon: const Icon(Icons.info_outline),
                    label: const Text('Status'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warning, foregroundColor: Colors.black),
              onPressed: _busy ? null : () => _dangerousAction('reboot'),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reboot droplet'),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: Colors.white),
              onPressed: _busy ? null : () => _dangerousAction('power_cycle'),
              icon: const Icon(Icons.power_settings_new),
              label: const Text('Power cycle (hard)'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _fetchStatus() async {
    setState(() => _busy = true);
    try {
      final client = await _client();
      final status = await client.getStatus(resourceId: widget.resourceId);
      setState(() => _statusLine =
          '${status.name}\nstatus: ${status.status}\nregion: ${status.region ?? '-'}\nipv4: ${status.ipv4.join(', ')}',);
      final server = await ref.read(serverProfileRepositoryProvider).getById(widget.serverId);
      await ref.read(auditRepositoryProvider).log(
            serverId: widget.serverId,
            serverNickname: server?.nickname,
            actionType: 'providerStatus',
            transport: 'providerApi',
            success: true,
            shortOutputSummary: _statusLine,
          );
    } catch (e) {
      setState(() => _statusLine = 'Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _dangerousAction(String type) async {
    final confirm = await DangerousConfirmDialog.show(
      context: context,
      title: type == 'reboot' ? 'Reboot droplet?' : 'Power cycle droplet?',
      description: type == 'reboot'
          ? 'Soft reboot via DigitalOcean API. Same as clicking Reboot in the console.'
          : 'HARD power cycle. Equivalent to pulling the plug — can cause data loss. Use only when soft reboot fails.',
    );
    if (!confirm) return;

    final gate = ref.read(biometricGateProvider);
    if (await gate.isAvailable()) {
      final ok = await gate.authenticate(reason: 'Confirm provider action');
      if (!ok) return;
    }

    setState(() => _busy = true);
    bool success = false;
    String? err;
    try {
      final client = await _client();
      if (type == 'reboot') {
        await client.reboot(resourceId: widget.resourceId);
      } else {
        await client.powerCycle(resourceId: widget.resourceId);
      }
      success = true;
    } catch (e) {
      err = e.toString();
    }

    final server = await ref.read(serverProfileRepositoryProvider).getById(widget.serverId);
    await ref.read(auditRepositoryProvider).log(
          serverId: widget.serverId,
          serverNickname: server?.nickname,
          actionType: type == 'reboot' ? 'providerReboot' : 'providerPowerCycle',
          transport: 'providerApi',
          success: success,
          rawCommand: null,
          shortOutputSummary: success ? '$type accepted by DigitalOcean' : null,
          errorSummary: err,
        );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _statusLine = success ? '$type accepted by DigitalOcean' : 'Failed: $err';
    });
  }
}

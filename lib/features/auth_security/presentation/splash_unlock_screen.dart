import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../command_templates/data/command_template_repository_impl.dart';
import '../../quick_actions/data/quick_action_repository_impl.dart';
import '../../settings/data/settings_repository.dart';
import '../data/biometric_gate_impl.dart';

/// First screen shown at launch. Seeds built-ins, checks biometric lock, then
/// routes into the server list.
class SplashUnlockScreen extends ConsumerStatefulWidget {
  const SplashUnlockScreen({super.key});

  @override
  ConsumerState<SplashUnlockScreen> createState() => _SplashUnlockScreenState();
}

class _SplashUnlockScreenState extends ConsumerState<SplashUnlockScreen> {
  String _status = 'Starting…';
  bool _lockMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    try {
      setState(() => _status = 'Preparing database…');
      await ref.read(commandTemplateRepositoryProvider).seedBuiltinsIfEmpty();
      await ref.read(quickActionRepositoryProvider).seedDefaultsIfEmpty();

      setState(() => _status = 'Checking lock…');
      final biometricOn = (await ref.read(settingsRepositoryProvider).get(SettingKeys.biometricLock)) == 'true';
      if (biometricOn) {
        final gate = ref.read(biometricGateProvider);
        if (await gate.isAvailable()) {
          setState(() {
            _lockMode = true;
            _status = 'Locked — authenticate to continue';
          });
          final ok = await gate.authenticate(reason: 'Unlock OpsPocket');
          if (!ok) {
            setState(() => _status = 'Authentication failed');
            return;
          }
        }
      }
      if (!mounted) return;
      context.go('/servers');
    } catch (e) {
      setState(() => _status = 'Startup error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.bolt, color: AppTheme.accent, size: 52),
                ),
                const SizedBox(height: 20),
                const Text('OpsPocket', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                  'Mobile recovery for VPS, bots, and AI services.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.muted),
                ),
                const SizedBox(height: 28),
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(height: 12),
                Text(_status, style: TextStyle(color: AppTheme.muted)),
                if (_lockMode) ...[
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _boot,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Unlock'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/core/errors/app_error.dart';
import '../../../app/core/utils/danger_detector.dart';
import '../../../app/core/utils/sanitizer.dart';
import '../../../app/core/widgets/dangerous_confirm_dialog.dart';
import '../../../shared/models/command_execution_result.dart';
import '../../audit/data/audit_repository_impl.dart';
import '../../auth_security/data/biometric_gate_impl.dart';
import '../../server_profiles/data/server_profile_repository_impl.dart';
import '../../settings/data/settings_repository.dart';
import 'ssh_connection_notifier.dart';

/// Orchestrates: danger check -> optional biometric -> SSH exec -> audit.
/// Kept centralized so Terminal, Quick Actions, and Logs all flow through
/// the same gates.
class CommandRunner {
  final Ref _ref;
  CommandRunner(this._ref);

  Future<CommandExecutionResult?> run({
    required BuildContext context,
    required String serverId,
    required String command,
    String? templateName,
    bool forceDangerous = false,
  }) async {
    if (command.trim().isEmpty) {
      throw const ValidationError('Empty command');
    }

    final settings = _ref.read(settingsRepositoryProvider);
    final dangerousOn = (await settings.get(SettingKeys.dangerousConfirmation)) != 'false';
    final biometricOn = (await settings.get(SettingKeys.biometricLock)) == 'true';

    final isDangerous = forceDangerous || DangerDetector.isDangerous(command);
    if (isDangerous && dangerousOn) {
      final ok = await DangerousConfirmDialog.show(
        context: context,
        title: 'Dangerous command',
        description: 'This command can cause downtime or data loss:\n\n$command\n\nType CONFIRM to proceed.',
      );
      if (!ok) return null;

      if (biometricOn) {
        final gate = _ref.read(biometricGateProvider);
        if (await gate.isAvailable()) {
          final authed = await gate.authenticate(reason: 'Confirm destructive action');
          if (!authed) {
            throw const BiometricDeniedError();
          }
        }
      }
    }

    // Ensure connection.
    final session = _ref.read(sshConnectionProvider(serverId));
    if (!_sessionReady(session.connectionState.name)) {
      await _ref.read(sshConnectionProvider(serverId).notifier).connect();
    }

    final client = _ref.read(sshClientProvider(serverId));
    final result = await client.exec(command);

    final profile = await _ref.read(serverProfileRepositoryProvider).getById(serverId);
    await _ref.read(auditRepositoryProvider).log(
          serverId: serverId,
          serverNickname: profile?.nickname,
          actionType: templateName != null ? 'runTemplate' : 'runCommand',
          transport: 'ssh',
          success: result.success,
          rawCommand: Sanitizer.sanitize(command),
          commandTemplateName: templateName,
          shortOutputSummary: Sanitizer.summarise(result.combinedOutput()),
          errorSummary: result.success ? null : Sanitizer.summarise(result.stderr.isEmpty ? 'Non-zero exit ${result.exitCode}' : result.stderr),
        );

    return result;
  }

  bool _sessionReady(String stateName) => stateName == 'connected';
}

final commandRunnerProvider = Provider<CommandRunner>((ref) => CommandRunner(ref));

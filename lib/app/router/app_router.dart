import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/audit/presentation/audit_screen.dart';
import '../../features/auth_security/presentation/splash_unlock_screen.dart';
import '../../features/splash/presentation/logo_splash_screen.dart';
import '../../features/command_templates/presentation/command_templates_screen.dart';
import '../../features/logs/presentation/logs_screen.dart';
import '../../features/quick_actions/presentation/quick_actions_screen.dart';
import '../../features/server_profiles/presentation/server_edit_screen.dart';
import '../../features/server_profiles/presentation/server_list_screen.dart';
import '../../features/server_profiles/presentation/server_detail_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/terminal/presentation/terminal_screen.dart';

/// Route names used across the app.
class Routes {
  Routes._();
  static const logoSplash = '/splash';
  static const splash = '/';
  static const servers = '/servers';
  static const serverAdd = '/servers/add';
  static const serverEdit = '/servers/:id/edit';
  static const serverDetail = '/servers/:id';
  static const terminal = '/servers/:id/terminal';
  static const quickActions = '/servers/:id/quick-actions';
  static const logs = '/servers/:id/logs';
  static const templates = '/templates';
  static const audit = '/audit';
  static const settings = '/settings';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.logoSplash,
    debugLogDiagnostics: false,
    routes: [
      GoRoute(
        path: Routes.logoSplash,
        builder: (context, state) => const LogoSplashScreen(),
      ),
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const SplashUnlockScreen(),
      ),
      GoRoute(
        path: Routes.servers,
        builder: (context, state) => const ServerListScreen(),
        routes: [
          GoRoute(
            path: 'add',
            builder: (context, state) => const ServerEditScreen(),
          ),
          GoRoute(
            path: ':id',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return ServerDetailScreen(serverId: id);
            },
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) {
                  final id = state.pathParameters['id']!;
                  return ServerEditScreen(serverId: id);
                },
              ),
              GoRoute(
                path: 'terminal',
                builder: (context, state) {
                  final id = state.pathParameters['id']!;
                  return TerminalScreen(serverId: id);
                },
              ),
              GoRoute(
                path: 'quick-actions',
                builder: (context, state) {
                  final id = state.pathParameters['id']!;
                  return QuickActionsScreen(serverId: id);
                },
              ),
              GoRoute(
                path: 'logs',
                builder: (context, state) {
                  final id = state.pathParameters['id']!;
                  return LogsScreen(serverId: id);
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: Routes.templates,
        builder: (context, state) => const CommandTemplatesScreen(),
      ),
      GoRoute(
        path: Routes.audit,
        builder: (context, state) => const AuditScreen(),
      ),
      GoRoute(
        path: Routes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Route error: ${state.error}',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
});

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ssh/domain/sftp_session.dart';
import '../../ssh/presentation/ssh_connection_notifier.dart';
import '../domain/sftp_browser_state.dart';

/// Per-server SFTP browser notifier. Opens one SFTP session on demand and
/// keeps it for the duration the browser screen is alive.
class SftpBrowserNotifier extends StateNotifier<SftpBrowserState> {
  final Ref _ref;
  final String _serverId;

  SftpSession? _session;

  SftpBrowserNotifier(this._ref, this._serverId)
      : super(const SftpBrowserState());

  /// Opens an SFTP session (if not already open) and navigates to the user's
  /// home directory. Safe to call multiple times — becomes a no-op if the
  /// session is already open and the screen is mounted.
  Future<void> open() async {
    if (_session != null && state.sessionOpen) return;
    state = state.copyWith(loading: true, clearFatal: true);
    try {
      final client = _ref.read(sshClientProvider(_serverId));
      if (!client.isConnected) {
        state = state.copyWith(
          loading: false,
          fatalError: 'SSH is not connected. Connect first, then try again.',
        );
        return;
      }
      final session = await client.openSftp();
      _session = session;
      final home = await session.homeDirectory();
      state = state.copyWith(
        sessionOpen: true,
        homePath: home,
      );
      await _load(home);
    } catch (e) {
      state = state.copyWith(
        loading: false,
        fatalError: 'Could not open SFTP: $e',
      );
    }
  }

  /// Changes directory and reloads entries.
  Future<void> navigateTo(String path) async {
    final normalised = normalizeSftpPath(path);
    await _load(normalised);
  }

  /// Reloads the current directory.
  Future<void> refresh() async {
    await _load(state.cwd);
  }

  Future<void> _load(String path) async {
    final session = _session;
    if (session == null) return;
    state = state.copyWith(loading: true, clearTransient: true);
    try {
      final entries = await session.listDirectory(path);
      state = state.copyWith(
        cwd: path,
        entries: entries,
        loading: false,
        clearFatal: true,
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        transientError: 'Could not list $path: $e',
      );
    }
  }

  Future<Uint8List?> readFile(String path) async {
    final session = _session;
    if (session == null) return null;
    try {
      return await session.readFile(path);
    } catch (e) {
      state = state.copyWith(transientError: 'Could not read $path: $e');
      return null;
    }
  }

  Future<bool> writeFile(String path, Uint8List data) async {
    final session = _session;
    if (session == null) return false;
    try {
      await session.writeFile(path, data);
      await refresh();
      return true;
    } catch (e) {
      state = state.copyWith(transientError: 'Could not write $path: $e');
      return false;
    }
  }

  Future<bool> deleteEntry(SftpEntry entry) async {
    final session = _session;
    if (session == null) return false;
    try {
      if (entry.isDirectory) {
        await session.deleteDirectory(entry.path);
      } else {
        await session.deleteFile(entry.path);
      }
      await refresh();
      return true;
    } catch (e) {
      state = state.copyWith(transientError: 'Delete failed: $e');
      return false;
    }
  }

  Future<bool> makeDirectory(String name) async {
    final session = _session;
    if (session == null) return false;
    final target = normalizeSftpPath('${state.cwd}/$name');
    try {
      await session.makeDirectory(target);
      await refresh();
      return true;
    } catch (e) {
      state = state.copyWith(transientError: 'mkdir failed: $e');
      return false;
    }
  }

  Future<bool> rename(SftpEntry entry, String newName) async {
    final session = _session;
    if (session == null) return false;
    final target = normalizeSftpPath('${state.cwd}/$newName');
    try {
      await session.rename(entry.path, target);
      await refresh();
      return true;
    } catch (e) {
      state = state.copyWith(transientError: 'Rename failed: $e');
      return false;
    }
  }

  /// Clears the current transient error without taking any action.
  void dismissTransientError() {
    state = state.copyWith(clearTransient: true);
  }

  @override
  void dispose() {
    final s = _session;
    _session = null;
    s?.close();
    super.dispose();
  }
}

final sftpBrowserProvider = StateNotifierProvider.family<
    SftpBrowserNotifier, SftpBrowserState, String>(
  (ref, serverId) => SftpBrowserNotifier(ref, serverId),
);

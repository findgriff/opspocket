import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../ssh/domain/sftp_session.dart';
import '../domain/sftp_browser_state.dart';
import 'sftp_notifier.dart';
import 'file_preview_screen.dart';

const int _previewSizeLimit = 1024 * 1024; // 1 MB

/// SFTP file browser for a single connected server.
class SftpBrowserScreen extends ConsumerStatefulWidget {
  final String serverId;
  const SftpBrowserScreen({super.key, required this.serverId});

  @override
  ConsumerState<SftpBrowserScreen> createState() => _SftpBrowserScreenState();
}

class _SftpBrowserScreenState extends ConsumerState<SftpBrowserScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(sftpBrowserProvider(widget.serverId).notifier).open();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sftpBrowserProvider(widget.serverId));
    final notifier = ref.read(sftpBrowserProvider(widget.serverId).notifier);

    // Surface transient errors as a SnackBar, then clear.
    final transientMsg = state.transientError;
    if (transientMsg != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(transientMsg),
            backgroundColor: AppTheme.danger.withValues(alpha: 0.9),
            duration: const Duration(seconds: 3),
          ),
        );
        notifier.dismissTransientError();
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Files (SFTP)'),
        actions: [
          if (state.homePath != null)
            IconButton(
              icon: const Icon(Icons.home_outlined),
              tooltip: 'Home',
              onPressed: () => notifier.navigateTo(state.homePath!),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: state.loading ? null : notifier.refresh,
          ),
        ],
      ),
      body: state.fatalError != null
          ? _FatalError(
              message: state.fatalError!, onRetry: notifier.open)
          : Column(
              children: [
                _Breadcrumb(
                    cwd: state.cwd, onTap: notifier.navigateTo),
                const Divider(height: 1),
                Expanded(child: _buildList(state, notifier)),
              ],
            ),
      floatingActionButton: state.fatalError != null || !state.sessionOpen
          ? null
          : _ActionFab(onAction: (action) => _handleFab(action, notifier)),
    );
  }

  Widget _buildList(SftpBrowserState state, SftpBrowserNotifier notifier) {
    if (state.entries.isEmpty && state.loading) {
      return const Center(
        child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (state.entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open,
                size: 42, color: AppTheme.muted.withValues(alpha: 0.5)),
            const SizedBox(height: 8),
            Text('Empty directory',
                style: AppTheme.mono(size: 12, color: AppTheme.muted)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: notifier.refresh,
      child: ListView.separated(
        itemCount: state.entries.length + 1,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          if (i == 0 && state.cwd != '/') {
            // Parent-directory pseudo-entry.
            return ListTile(
              leading: Icon(Icons.arrow_upward, color: AppTheme.cyan),
              title: Text('..',
                  style: AppTheme.mono(size: 14, color: AppTheme.cyan)),
              subtitle: Text('Parent directory',
                  style: AppTheme.mono(size: 11, color: AppTheme.muted)),
              onTap: () => notifier.navigateTo(parentOf(state.cwd)),
            );
          }
          final entry =
              state.entries[state.cwd == '/' ? i : i - 1];
          return _EntryRow(
            entry: entry,
            onTap: () => _handleEntryTap(entry, notifier),
            onLongPress: () => _handleEntryLongPress(entry, notifier),
          );
        },
      ),
    );
  }

  Future<void> _handleEntryTap(
      SftpEntry entry, SftpBrowserNotifier notifier) async {
    if (entry.isDirectory) {
      await notifier.navigateTo(entry.path);
      return;
    }
    if (entry.isSymlink) {
      // Try to follow — if it's a dir the list will succeed, otherwise we
      // fall back to preview.
      try {
        await notifier.navigateTo(entry.path);
        return;
      } catch (_) {
        /* fall through to preview */
      }
    }
    await _previewFile(entry, notifier);
  }

  Future<void> _previewFile(
      SftpEntry entry, SftpBrowserNotifier notifier) async {
    if (entry.size > _previewSizeLimit) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('File is large'),
          content: Text(
              'This file is ${_bytes(entry.size)}. Previewing in-app may be slow. Continue?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Preview')),
          ],
        ),
      );
      if (proceed != true) return;
    }
    if (!mounted) return;
    final bytes = await notifier.readFile(entry.path);
    if (!mounted || bytes == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FilePreviewScreen(
        path: entry.path,
        bytes: bytes,
      ),
    ));
  }

  Future<void> _handleEntryLongPress(
      SftpEntry entry, SftpBrowserNotifier notifier) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF2A2A2A),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(entry.name,
                  style: AppTheme.mono(size: 13, weight: FontWeight.w700)),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.content_copy),
              title: const Text('Copy path'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: AppTheme.danger),
              title: Text('Delete',
                  style: TextStyle(color: AppTheme.danger)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'rename') {
      final next = await _promptText(
        title: 'Rename "${entry.name}"',
        initial: entry.name,
      );
      if (next != null && next.isNotEmpty && next != entry.name) {
        await notifier.rename(entry, next);
      }
    } else if (choice == 'copy') {
      await Clipboard.setData(ClipboardData(text: entry.path));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Path copied to clipboard')));
    } else if (choice == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Delete ${entry.isDirectory ? 'folder' : 'file'}?'),
          content: Text(
              'This will permanently delete "${entry.name}" on the server. This cannot be undone.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Delete', style: TextStyle(color: AppTheme.danger)),
            ),
          ],
        ),
      );
      if (ok == true) await notifier.deleteEntry(entry);
    }
  }

  Future<void> _handleFab(
      String action, SftpBrowserNotifier notifier) async {
    switch (action) {
      case 'upload':
        await _uploadFile(notifier);
        break;
      case 'mkdir':
        final name = await _promptText(
            title: 'New folder', hint: 'folder name');
        if (name != null && name.isNotEmpty) {
          await notifier.makeDirectory(name);
        }
        break;
    }
  }

  Future<void> _uploadFile(SftpBrowserNotifier notifier) async {
    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      allowMultiple: false,
    );
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.first;

    Uint8List? bytes = f.bytes;
    if (bytes == null && f.path != null) {
      // On iOS, the picker may return a cached path rather than bytes
      // when the file is large.
      try {
        bytes = await File(f.path!).readAsBytes();
      } catch (_) {
        bytes = null;
      }
    }
    if (bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read picked file')));
      return;
    }

    final targetName = await _promptText(
      title: 'Upload as',
      initial: f.name,
    );
    if (targetName == null || targetName.isEmpty) return;
    final targetPath =
        normalizeSftpPath('${ref.read(sftpBrowserProvider(widget.serverId)).cwd}/$targetName');
    final ok = await notifier.writeFile(targetPath, bytes);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Uploaded $targetName' : 'Upload failed'),
    ));
  }

  Future<String?> _promptText(
      {required String title, String? hint, String? initial}) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          style: AppTheme.mono(size: 14),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return result;
  }

  static String _bytes(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    if (n < 1024 * 1024 * 1024) return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(n / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class _Breadcrumb extends StatelessWidget {
  final String cwd;
  final void Function(String) onTap;
  const _Breadcrumb({required this.cwd, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final crumbs = breadcrumbsFor(cwd);
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: Row(
          children: [
            for (var i = 0; i < crumbs.length; i++) ...[
              InkWell(
                onTap: () => onTap(crumbs[i].path),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 4),
                  child: Text(
                    crumbs[i].label,
                    style: AppTheme.mono(
                      size: 12,
                      color: i == crumbs.length - 1
                          ? AppTheme.cyan
                          : AppTheme.muted,
                      weight: i == crumbs.length - 1
                          ? FontWeight.w700
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
              if (i < crumbs.length - 1)
                Text('›',
                    style:
                        AppTheme.mono(size: 12, color: AppTheme.muted)),
            ],
          ],
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  final SftpEntry entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _EntryRow(
      {required this.entry,
      required this.onTap,
      required this.onLongPress});

  IconData get _icon {
    if (entry.isDirectory) return Icons.folder_rounded;
    if (entry.isSymlink) return Icons.link;
    return _iconForFilename(entry.name);
  }

  static IconData _iconForFilename(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.log') || lower.endsWith('.out')) {
      return Icons.description_outlined;
    }
    if (lower.endsWith('.sh') ||
        lower.endsWith('.bash') ||
        lower.endsWith('.zsh')) {
      return Icons.code;
    }
    if (lower.endsWith('.json') ||
        lower.endsWith('.yaml') ||
        lower.endsWith('.yml') ||
        lower.endsWith('.toml') ||
        lower.endsWith('.env') ||
        lower.endsWith('.conf') ||
        lower.endsWith('.cfg') ||
        lower.endsWith('.ini')) {
      return Icons.settings_outlined;
    }
    if (lower.endsWith('.txt') || lower.endsWith('.md')) {
      return Icons.notes;
    }
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final c = entry.isDirectory
        ? AppTheme.cyan
        : (entry.isSymlink ? AppTheme.warning : AppTheme.muted);
    final subtitle = entry.isDirectory
        ? (entry.modified != null ? _relative(entry.modified!) : 'folder')
        : '${_sizeLabel(entry.size)}'
            '${entry.modified != null ? '  •  ${_relative(entry.modified!)}' : ''}';

    return ListTile(
      leading: Icon(_icon, color: c),
      title: Text(
        entry.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTheme.mono(
          size: 14,
          weight: entry.isDirectory ? FontWeight.w700 : FontWeight.normal,
        ),
      ),
      subtitle: Text(subtitle,
          style: AppTheme.mono(size: 11, color: AppTheme.muted)),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  static String _sizeLabel(int n) {
    if (n <= 0) return '0 B';
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    if (n < 1024 * 1024 * 1024) return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(n / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String _relative(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inDays > 180) {
      return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    }
    if (d.inDays > 1) return '${d.inDays}d ago';
    if (d.inHours > 1) return '${d.inHours}h ago';
    if (d.inMinutes > 1) return '${d.inMinutes}m ago';
    return 'just now';
  }
}

class _ActionFab extends StatelessWidget {
  final void Function(String action) onAction;
  const _ActionFab({required this.onAction});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FloatingActionButton.small(
          heroTag: 'sftp-mkdir',
          backgroundColor: const Color(0xFF2A2A2A),
          foregroundColor: AppTheme.cyan,
          onPressed: () => onAction('mkdir'),
          child: const Icon(Icons.create_new_folder_outlined),
        ),
        const SizedBox(height: 10),
        FloatingActionButton(
          heroTag: 'sftp-upload',
          backgroundColor: AppTheme.accent,
          onPressed: () => onAction('upload'),
          child: const Icon(Icons.file_upload_outlined),
        ),
      ],
    );
  }
}

class _FatalError extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _FatalError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: AppTheme.danger),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: AppTheme.mono(size: 12, color: AppTheme.muted)),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: () => onRetry(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(140, 44),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.pop(),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}

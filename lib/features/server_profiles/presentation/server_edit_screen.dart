import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../app/theme/app_theme.dart';
import '../../../shared/models/server_profile.dart';
import '../../../shared/storage/secure_storage.dart';
import '../data/server_profile_repository_impl.dart';

/// Add or edit a server profile. Private key body is stored in secure storage
/// and referenced by secureStorageKey; it never touches the Drift DB.
class ServerEditScreen extends ConsumerStatefulWidget {
  final String? serverId;
  const ServerEditScreen({super.key, this.serverId});

  @override
  ConsumerState<ServerEditScreen> createState() => _ServerEditScreenState();
}

class _ServerEditScreenState extends ConsumerState<ServerEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nickname = TextEditingController();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '22');
  final _user = TextEditingController();
  final _tags = TextEditingController();
  final _notes = TextEditingController();
  final _privateKey = TextEditingController();
  final _passphrase = TextEditingController();
  final _password = TextEditingController();
  final _providerResourceId = TextEditingController();

  SshAuthMethod _auth = SshAuthMethod.privateKey;
  ProviderType _provider = ProviderType.none;
  bool _loading = true;
  bool _saving = false;
  ServerProfile? _existing;

  bool get _isEdit => widget.serverId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_isEdit) {
      setState(() => _loading = false);
      return;
    }
    final repo = ref.read(serverProfileRepositoryProvider);
    final p = await repo.getById(widget.serverId!);
    if (!mounted) return;
    if (p == null) {
      setState(() => _loading = false);
      return;
    }
    _existing = p;
    _nickname.text = p.nickname;
    _host.text = p.hostnameOrIp;
    _port.text = p.port.toString();
    _user.text = p.username;
    _tags.text = p.tags.join(', ');
    _notes.text = p.notes ?? '';
    _auth = p.authMethod;
    _provider = p.providerType;
    _providerResourceId.text = p.providerResourceId ?? '';
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _nickname.dispose();
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _tags.dispose();
    _notes.dispose();
    _privateKey.dispose();
    _passphrase.dispose();
    _password.dispose();
    _providerResourceId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit server' : 'Add server'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _confirmDelete,
            ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _label('Nickname'),
                TextFormField(
                  controller: _nickname,
                  decoration: const InputDecoration(hintText: 'production-bot'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                _label('Host or IP'),
                TextFormField(
                  controller: _host,
                  decoration: const InputDecoration(hintText: '1.2.3.4 or bot.example.com'),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _label('Port'),
                          TextFormField(
                            controller: _port,
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              final n = int.tryParse(v?.trim() ?? '');
                              if (n == null || n < 1 || n > 65535) return '1–65535';
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _label('Username'),
                          TextFormField(
                            controller: _user,
                            autocorrect: false,
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _label('Authentication'),
                SegmentedButton<SshAuthMethod>(
                  segments: const [
                    ButtonSegment(value: SshAuthMethod.privateKey, label: Text('Private key')),
                    ButtonSegment(value: SshAuthMethod.passwordNotStored, label: Text('Password')),
                  ],
                  selected: {_auth},
                  onSelectionChanged: (s) => setState(() => _auth = s.first),
                ),
                const SizedBox(height: 12),
                if (_auth == SshAuthMethod.privateKey) ...[
                  _label(_isEdit ? 'Replace private key (leave blank to keep)' : 'Private key (PEM)'),
                  TextFormField(
                    controller: _privateKey,
                    maxLines: 5,
                    style: AppTheme.mono(size: 12),
                    decoration: const InputDecoration(
                      hintText: '-----BEGIN OPENSSH PRIVATE KEY-----\n...',
                    ),
                    autocorrect: false,
                    validator: (v) {
                      if (!_isEdit && (v == null || v.trim().isEmpty)) {
                        return 'Required for private key auth';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  _label('Passphrase (optional)'),
                  TextFormField(
                    controller: _passphrase,
                    obscureText: true,
                  ),
                ] else ...[
                  _label(_isEdit ? 'Password (leave blank to keep)' : 'Password'),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(hintText: 'SSH password'),
                    validator: (v) {
                      if (!_isEdit && (v == null || v.trim().isEmpty)) {
                        return 'Required for password auth';
                      }
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 20),
                _label('Tags (comma-separated)'),
                TextFormField(
                  controller: _tags,
                  decoration: const InputDecoration(hintText: 'prod, bot, claude'),
                ),
                const SizedBox(height: 16),
                _label('Notes'),
                TextFormField(
                  controller: _notes,
                  maxLines: 3,
                ),
                const SizedBox(height: 20),
                _label('Provider (optional)'),
                DropdownButtonFormField<ProviderType>(
                  initialValue: _provider,
                  items: ProviderType.values
                      .map((p) => DropdownMenuItem(value: p, child: Text(_providerLabel(p))))
                      .toList(),
                  onChanged: (v) => setState(() => _provider = v ?? ProviderType.none),
                ),
                if (_provider == ProviderType.digitalOcean) ...[
                  const SizedBox(height: 12),
                  _label('Droplet ID'),
                  TextFormField(
                    controller: _providerResourceId,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: '123456789'),
                  ),
                ],
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Saving…' : 'Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _providerLabel(ProviderType p) {
    switch (p) {
      case ProviderType.none:
        return 'None';
      case ProviderType.digitalOcean:
        return 'DigitalOcean';
      case ProviderType.aws:
        return 'AWS (coming soon)';
      case ProviderType.hetzner:
        return 'Hetzner (coming soon)';
      case ProviderType.linode:
        return 'Linode (coming soon)';
      case ProviderType.custom:
        return 'Custom';
    }
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(text, style: TextStyle(color: AppTheme.muted, fontSize: 12)),
      );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final repo = ref.read(serverProfileRepositoryProvider);
      final storage = ref.read(secureStorageProvider);
      final id = widget.serverId ?? const Uuid().v4();

      String? secureKey = _existing?.secureStorageKey;
      bool hasPassphrase = _existing?.hasPassphrase ?? false;

      if (_auth == SshAuthMethod.privateKey) {
        if (_privateKey.text.trim().isNotEmpty) {
          secureKey = SecretKeys.sshPrivateKey(id);
          await storage.write(key: secureKey, value: _privateKey.text.trim());
        }
        if (_passphrase.text.isNotEmpty) {
          await storage.write(key: SecretKeys.sshKeyPassphrase(id), value: _passphrase.text);
          hasPassphrase = true;
        }
      } else {
        secureKey = null;
        hasPassphrase = false;
        if (_password.text.isNotEmpty) {
          await storage.write(key: SecretKeys.sshPassword(id), value: _password.text);
        }
      }

      final now = DateTime.now();
      final p = ServerProfile(
        id: id,
        nickname: _nickname.text.trim(),
        hostnameOrIp: _host.text.trim(),
        port: int.parse(_port.text.trim()),
        username: _user.text.trim(),
        authMethod: _auth,
        privateKeyLabel: _auth == SshAuthMethod.privateKey
            ? (_isEdit ? _existing?.privateKeyLabel ?? 'Imported key' : 'Imported key')
            : null,
        secureStorageKey: secureKey,
        hasPassphrase: hasPassphrase,
        tags: _tags.text
            .split(',')
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        providerType: _provider,
        providerResourceId:
            _providerResourceId.text.trim().isEmpty ? null : _providerResourceId.text.trim(),
        isFavorite: _existing?.isFavorite ?? false,
        lastConnectedAt: _existing?.lastConnectedAt,
        createdAt: _existing?.createdAt ?? now,
        updatedAt: now,
      );

      await repo.upsert(p);
      if (!mounted) return;
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete server?'),
        content: const Text('This removes the profile and its stored key. Audit history is kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(serverProfileRepositoryProvider).delete(widget.serverId!);
    if (!mounted) return;
    context.go('/servers');
  }
}

import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../domain/sftp_session.dart';

/// dartssh2-backed SFTP session. Stays behind [SftpSession] so feature code
/// never has to touch the library directly.
class DartSsh2SftpSession implements SftpSession {
  final SftpClient _sftp;
  bool _open = true;

  DartSsh2SftpSession(this._sftp);

  @override
  bool get isOpen => _open;

  @override
  Future<String> homeDirectory() async {
    try {
      // "" resolves to the user's home on most OpenSSH servers.
      final home = await _sftp.absolute('.');
      if (home.isNotEmpty) return home;
    } catch (_) {
      /* fall through */
    }
    return '/';
  }

  @override
  Future<List<SftpEntry>> listDirectory(String path) async {
    final raw = await _sftp.listdir(path);
    final entries = <SftpEntry>[];
    for (final n in raw) {
      // dartssh2 includes "." and ".." in listings — filter out so we only
      // surface actual children.
      if (n.filename == '.' || n.filename == '..') continue;
      entries.add(_toEntry(path, n));
    }
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  SftpEntry _toEntry(String dir, SftpName raw) {
    final attrs = raw.attr;
    SftpEntryKind kind;
    if (attrs.isDirectory) {
      kind = SftpEntryKind.directory;
    } else if (attrs.isSymbolicLink) {
      kind = SftpEntryKind.symlink;
    } else if (attrs.isFile) {
      kind = SftpEntryKind.file;
    } else {
      kind = SftpEntryKind.other;
    }

    final mtime = attrs.modifyTime;
    DateTime? modified;
    if (mtime != null) {
      modified = DateTime.fromMillisecondsSinceEpoch(mtime * 1000, isUtc: true)
          .toLocal();
    }

    // `longname` is ls -l style; the first token is the mode string if the
    // server gave it. We surface it only as a display hint, never for auth.
    String? mode;
    final ln = raw.longname.trim();
    if (ln.isNotEmpty) {
      final firstToken = ln.split(RegExp(r'\s+')).first;
      if (RegExp(r'^[-dlbcps][-rwxsStT]{9}').hasMatch(firstToken)) {
        mode = firstToken;
      }
    }

    return SftpEntry(
      name: raw.filename,
      path: _join(dir, raw.filename),
      kind: kind,
      size: attrs.size ?? 0,
      modified: modified,
      mode: mode,
    );
  }

  String _join(String dir, String name) {
    if (dir.endsWith('/')) return '$dir$name';
    return '$dir/$name';
  }

  @override
  Future<Uint8List> readFile(String path) async {
    final file = await _sftp.open(path, mode: SftpFileOpenMode.read);
    try {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in file.read()) {
        builder.add(chunk);
      }
      return builder.toBytes();
    } finally {
      try {
        await file.close();
      } catch (_) {}
    }
  }

  @override
  Future<void> writeFile(String path, Uint8List bytes) async {
    final file = await _sftp.open(
      path,
      mode: SftpFileOpenMode.write |
          SftpFileOpenMode.create |
          SftpFileOpenMode.truncate,
    );
    try {
      await file.writeBytes(bytes);
    } finally {
      try {
        await file.close();
      } catch (_) {}
    }
  }

  @override
  Future<void> deleteFile(String path) async {
    await _sftp.remove(path);
  }

  @override
  Future<void> deleteDirectory(String path) async {
    await _sftp.rmdir(path);
  }

  @override
  Future<void> makeDirectory(String path) async {
    await _sftp.mkdir(path);
  }

  @override
  Future<void> rename(String from, String to) async {
    await _sftp.rename(from, to);
  }

  @override
  Future<void> close() async {
    if (!_open) return;
    _open = false;
    try {
      _sftp.close();
    } catch (_) {}
  }
}

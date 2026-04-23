import '../../ssh/domain/sftp_session.dart';

/// View-model state for the SFTP browser.
class SftpBrowserState {
  /// Whether we've authenticated and opened an SFTP session yet.
  final bool sessionOpen;

  /// Current absolute directory being shown.
  final String cwd;

  /// Entries at [cwd]. Empty until the first successful listDir.
  final List<SftpEntry> entries;

  /// True while a list/read/write is in flight.
  final bool loading;

  /// Last non-fatal error (e.g. failed mkdir) to display as a toast.
  final String? transientError;

  /// Fatal error — when set, [entries] is whatever we had before.
  final String? fatalError;

  /// User's detected home directory (set on first open).
  final String? homePath;

  const SftpBrowserState({
    this.sessionOpen = false,
    this.cwd = '/',
    this.entries = const [],
    this.loading = false,
    this.transientError,
    this.fatalError,
    this.homePath,
  });

  SftpBrowserState copyWith({
    bool? sessionOpen,
    String? cwd,
    List<SftpEntry>? entries,
    bool? loading,
    String? transientError,
    String? fatalError,
    bool clearTransient = false,
    bool clearFatal = false,
    String? homePath,
  }) {
    return SftpBrowserState(
      sessionOpen: sessionOpen ?? this.sessionOpen,
      cwd: cwd ?? this.cwd,
      entries: entries ?? this.entries,
      loading: loading ?? this.loading,
      transientError:
          clearTransient ? null : (transientError ?? this.transientError),
      fatalError: clearFatal ? null : (fatalError ?? this.fatalError),
      homePath: homePath ?? this.homePath,
    );
  }
}

/// Normalise an absolute SFTP path — collapses ".." / "." and removes empty
/// segments. Always returns an absolute path starting with "/".
String normalizeSftpPath(String path) {
  if (path.isEmpty) return '/';
  final isAbs = path.startsWith('/');
  final segments = <String>[];
  for (final raw in path.split('/')) {
    if (raw.isEmpty || raw == '.') continue;
    if (raw == '..') {
      if (segments.isNotEmpty) segments.removeLast();
      continue;
    }
    segments.add(raw);
  }
  final joined = segments.join('/');
  if (!isAbs) return joined; // caller asked for relative — respect it
  return '/$joined';
}

/// Splits an absolute path into ordered ancestor paths for breadcrumb
/// rendering. `/home/clawd/logs` → `[(/, '/'), (home, /home), (clawd,
/// /home/clawd), (logs, /home/clawd/logs)]`.
List<({String label, String path})> breadcrumbsFor(String path) {
  final normalised = normalizeSftpPath(path);
  final out = <({String label, String path})>[
    (label: '/', path: '/'),
  ];
  if (normalised == '/') return out;
  final parts = normalised.split('/').where((s) => s.isNotEmpty).toList();
  final acc = StringBuffer();
  for (final p in parts) {
    acc.write('/');
    acc.write(p);
    out.add((label: p, path: acc.toString()));
  }
  return out;
}

/// Returns the parent directory of [path], or '/' if already at root.
String parentOf(String path) {
  final n = normalizeSftpPath(path);
  if (n == '/') return '/';
  final slash = n.lastIndexOf('/');
  if (slash <= 0) return '/';
  return n.substring(0, slash);
}

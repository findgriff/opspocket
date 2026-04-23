import 'dart:typed_data';

/// Entry type returned by directory listings.
enum SftpEntryKind { file, directory, symlink, other }

/// One entry in an SFTP directory listing.
class SftpEntry {
  final String name;
  final String path;
  final SftpEntryKind kind;
  final int size;
  final DateTime? modified;
  final String? mode; // "-rwxr-xr--" etc., best-effort

  const SftpEntry({
    required this.name,
    required this.path,
    required this.kind,
    required this.size,
    this.modified,
    this.mode,
  });

  bool get isDirectory => kind == SftpEntryKind.directory;
  bool get isSymlink => kind == SftpEntryKind.symlink;
  bool get isFile => kind == SftpEntryKind.file;
}

/// Abstraction over an open SFTP session. Implementations must be safe to
/// close multiple times. Never expose dartssh2 types across this boundary —
/// feature code should only ever see the domain types declared here.
abstract class SftpSession {
  /// Whether the underlying channel is still usable.
  bool get isOpen;

  /// Resolves and returns the absolute path of the current user's home
  /// directory. Best-effort — falls back to "/" if the server won't say.
  Future<String> homeDirectory();

  /// Lists the given absolute directory, sorted with directories first,
  /// then filename case-insensitive.
  Future<List<SftpEntry>> listDirectory(String path);

  /// Reads the entire file at [path] as raw bytes. Callers should check
  /// [SftpEntry.size] beforehand and refuse anything too large to fit in
  /// memory — there is no streaming preview helper here.
  Future<Uint8List> readFile(String path);

  /// Writes [bytes] to [path], creating or truncating. Returns normally if
  /// the server accepted the data.
  Future<void> writeFile(String path, Uint8List bytes);

  /// Deletes a regular file or symlink. Throws if [path] is a directory.
  Future<void> deleteFile(String path);

  /// Removes an empty directory. Throws on non-empty.
  Future<void> deleteDirectory(String path);

  /// Creates directory [path]. Non-recursive.
  Future<void> makeDirectory(String path);

  /// Renames / moves [from] to [to]. Both must be absolute.
  Future<void> rename(String from, String to);

  /// Closes the SFTP channel. Safe to call multiple times.
  Future<void> close();
}

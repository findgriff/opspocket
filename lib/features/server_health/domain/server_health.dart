/// A point-in-time snapshot of a server's resource usage.
///
/// Built from the combined output of:
///   uptime; free -b; df -B1 /; cat /proc/loadavg; nproc
///
/// All fields are nullable because some probes may fail on lean VPS images
/// (e.g. containers without `/proc/loadavg`) — the UI should degrade
/// gracefully rather than show zero-valued tiles.
class ServerHealthSnapshot {
  /// UTC timestamp the probe finished.
  final DateTime takenAt;

  /// Load averages from `/proc/loadavg` (1, 5, 15 min).
  final double? load1;
  final double? load5;
  final double? load15;

  /// Logical CPU count from `nproc`.
  final int? cpuCores;

  /// RAM, bytes. From `free -b`.
  final int? memTotalBytes;
  final int? memUsedBytes;
  final int? memAvailableBytes;

  /// Swap, bytes. From `free -b`.
  final int? swapTotalBytes;
  final int? swapUsedBytes;

  /// Root filesystem, bytes. From `df -B1 /`.
  final int? diskTotalBytes;
  final int? diskUsedBytes;
  final int? diskAvailableBytes;
  final String? diskMountPoint;

  /// Uptime, seconds.
  final int? uptimeSeconds;

  const ServerHealthSnapshot({
    required this.takenAt,
    this.load1,
    this.load5,
    this.load15,
    this.cpuCores,
    this.memTotalBytes,
    this.memUsedBytes,
    this.memAvailableBytes,
    this.swapTotalBytes,
    this.swapUsedBytes,
    this.diskTotalBytes,
    this.diskUsedBytes,
    this.diskAvailableBytes,
    this.diskMountPoint,
    this.uptimeSeconds,
  });

  /// 1-minute load as a percentage of available cores. Null if either the
  /// load or core count is unknown. Values >100% mean the run-queue exceeds
  /// the number of cores (saturated).
  double? get cpuLoadPercent {
    if (load1 == null || cpuCores == null || cpuCores! <= 0) return null;
    return (load1! / cpuCores!) * 100.0;
  }

  double? get memUsedPercent {
    if (memTotalBytes == null || memTotalBytes! <= 0 || memUsedBytes == null) {
      return null;
    }
    return (memUsedBytes! / memTotalBytes!) * 100.0;
  }

  double? get diskUsedPercent {
    if (diskTotalBytes == null ||
        diskTotalBytes! <= 0 ||
        diskUsedBytes == null) {
      return null;
    }
    return (diskUsedBytes! / diskTotalBytes!) * 100.0;
  }

  bool get hasAnyData =>
      load1 != null ||
      memTotalBytes != null ||
      diskTotalBytes != null ||
      uptimeSeconds != null;
}

/// Single remote probe composed of shell commands with guard markers.
/// Keep this free of quoting pitfalls — it runs through `exec`, not a PTY.
const String serverHealthProbeCommand = '''
echo "---OPSPOCKET-HEALTH-BEGIN---"
echo "===UPTIME==="
cat /proc/uptime 2>/dev/null || echo
echo "===LOAD==="
cat /proc/loadavg 2>/dev/null || echo
echo "===CORES==="
nproc 2>/dev/null || echo
echo "===MEM==="
free -b 2>/dev/null || echo
echo "===DISK==="
df -B1 / 2>/dev/null || echo
echo "---OPSPOCKET-HEALTH-END---"
''';

/// Parses the output of [serverHealthProbeCommand] into a
/// [ServerHealthSnapshot]. Missing or malformed sections are surfaced as
/// nulls rather than thrown errors — partial data is always better than
/// none for a status tile.
class ServerHealthParser {
  const ServerHealthParser();

  ServerHealthSnapshot parse(String stdout, {DateTime? now}) {
    final takenAt = now ?? DateTime.now().toUtc();
    final sections = _splitSections(stdout);

    // /proc/uptime: "12345.67 6789.01"
    final up = sections['UPTIME']?.trim();
    int? uptimeSeconds;
    if (up != null && up.isNotEmpty) {
      final first = up.split(RegExp(r'\s+')).first;
      final asDouble = double.tryParse(first);
      if (asDouble != null) uptimeSeconds = asDouble.round();
    }

    // /proc/loadavg: "0.12 0.34 0.56 1/234 5678"
    final load = sections['LOAD']?.trim();
    double? l1, l5, l15;
    if (load != null && load.isNotEmpty) {
      final parts = load.split(RegExp(r'\s+'));
      if (parts.length >= 3) {
        l1 = double.tryParse(parts[0]);
        l5 = double.tryParse(parts[1]);
        l15 = double.tryParse(parts[2]);
      }
    }

    // nproc: single integer
    int? cores;
    final coresTxt = sections['CORES']?.trim();
    if (coresTxt != null && coresTxt.isNotEmpty) {
      cores = int.tryParse(coresTxt);
    }

    // free -b: header row, "Mem:" row, "Swap:" row.
    int? memTotal, memUsed, memAvail, swapTotal, swapUsed;
    final mem = sections['MEM'];
    if (mem != null) {
      for (final line in mem.split('\n')) {
        final t = line.trim();
        if (t.startsWith('Mem:')) {
          final parts = t.split(RegExp(r'\s+'));
          // Mem:  total  used  free  shared  buff/cache  available
          if (parts.length >= 4) {
            memTotal = int.tryParse(parts[1]);
            memUsed = int.tryParse(parts[2]);
          }
          if (parts.length >= 7) memAvail = int.tryParse(parts[6]);
        } else if (t.startsWith('Swap:')) {
          final parts = t.split(RegExp(r'\s+'));
          if (parts.length >= 3) {
            swapTotal = int.tryParse(parts[1]);
            swapUsed = int.tryParse(parts[2]);
          }
        }
      }
    }

    // df -B1 /: header, then `<fs> <1B-blocks> <used> <available> <use%> <mount>`
    int? diskTotal, diskUsed, diskAvail;
    String? mount;
    final disk = sections['DISK'];
    if (disk != null) {
      final lines = disk.split('\n').where((l) => l.trim().isNotEmpty).toList();
      if (lines.length >= 2) {
        final parts = lines[1].trim().split(RegExp(r'\s+'));
        if (parts.length >= 6) {
          diskTotal = int.tryParse(parts[1]);
          diskUsed = int.tryParse(parts[2]);
          diskAvail = int.tryParse(parts[3]);
          mount = parts.last;
        }
      }
    }

    return ServerHealthSnapshot(
      takenAt: takenAt,
      load1: l1,
      load5: l5,
      load15: l15,
      cpuCores: cores,
      memTotalBytes: memTotal,
      memUsedBytes: memUsed,
      memAvailableBytes: memAvail,
      swapTotalBytes: swapTotal,
      swapUsedBytes: swapUsed,
      diskTotalBytes: diskTotal,
      diskUsedBytes: diskUsed,
      diskAvailableBytes: diskAvail,
      diskMountPoint: mount,
      uptimeSeconds: uptimeSeconds,
    );
  }

  Map<String, String> _splitSections(String raw) {
    // Strip anything outside the BEGIN/END markers so shell MOTDs can't
    // contaminate section headers.
    final begin = raw.indexOf('---OPSPOCKET-HEALTH-BEGIN---');
    final end = raw.indexOf('---OPSPOCKET-HEALTH-END---');
    final body = (begin >= 0 && end > begin)
        ? raw.substring(begin, end)
        : raw;

    final sections = <String, String>{};
    String? currentKey;
    final buf = StringBuffer();

    void flush() {
      final key = currentKey;
      if (key != null) {
        sections[key] = buf.toString();
      }
      buf.clear();
    }

    final markerRegex = RegExp(r'^===(\w+)===\s*$');
    for (final line in body.split('\n')) {
      final m = markerRegex.firstMatch(line);
      if (m != null) {
        flush();
        currentKey = m.group(1);
      } else if (currentKey != null) {
        buf.writeln(line);
      }
    }
    flush();
    return sections;
  }
}

/// Formats [bytes] as a short human-readable string (e.g. "1.2 GB").
String formatBytes(int? bytes) {
  if (bytes == null) return '–';
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  if (bytes < 0) return '$bytes B';
  if (bytes == 0) return '0 B';
  var value = bytes.toDouble();
  var i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  final digits = value >= 100 ? 0 : (value >= 10 ? 1 : 2);
  return '${value.toStringAsFixed(digits)} ${units[i]}';
}

/// Formats an uptime duration in seconds as e.g. "3d 4h", "12h 5m", "7m".
String formatUptime(int? seconds) {
  if (seconds == null || seconds < 0) return '–';
  final days = seconds ~/ 86400;
  final hours = (seconds % 86400) ~/ 3600;
  final mins = (seconds % 3600) ~/ 60;
  if (days > 0) return '${days}d ${hours}h';
  if (hours > 0) return '${hours}h ${mins}m';
  return '${mins}m';
}

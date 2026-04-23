import 'package:flutter_test/flutter_test.dart';
import 'package:opspocket/features/server_health/domain/server_health.dart';

void main() {
  const parser = ServerHealthParser();

  group('ServerHealthParser', () {
    test('parses full realistic output', () {
      const raw = '''
some MOTD noise that should be ignored
---OPSPOCKET-HEALTH-BEGIN---
===UPTIME===
123456.78 123000.00
===LOAD===
0.52 0.41 0.39 1/234 5678
===CORES===
4
===MEM===
              total        used        free      shared  buff/cache   available
Mem:     2095104000   734003200   350000000     1048576   1011100800  1215001600
Swap:     524288000           0   524288000
===DISK===
Filesystem        1B-blocks        Used   Available Use% Mounted on
/dev/sda1      52428800000 20000000000  30000000000  40% /
---OPSPOCKET-HEALTH-END---
''';
      final s = parser.parse(raw);
      expect(s.uptimeSeconds, 123457); // rounded
      expect(s.load1, 0.52);
      expect(s.load5, 0.41);
      expect(s.load15, 0.39);
      expect(s.cpuCores, 4);
      expect(s.memTotalBytes, 2095104000);
      expect(s.memUsedBytes, 734003200);
      expect(s.memAvailableBytes, 1215001600);
      expect(s.swapTotalBytes, 524288000);
      expect(s.swapUsedBytes, 0);
      expect(s.diskTotalBytes, 52428800000);
      expect(s.diskUsedBytes, 20000000000);
      expect(s.diskAvailableBytes, 30000000000);
      expect(s.diskMountPoint, '/');
      expect(s.cpuLoadPercent, closeTo(13.0, 0.1));
      expect(s.memUsedPercent, closeTo(35.03, 0.1));
      expect(s.diskUsedPercent, closeTo(38.14, 0.1));
    });

    test('tolerates missing sections', () {
      const raw = '''
---OPSPOCKET-HEALTH-BEGIN---
===UPTIME===
42.0 21.0
---OPSPOCKET-HEALTH-END---
''';
      final s = parser.parse(raw);
      expect(s.uptimeSeconds, 42);
      expect(s.load1, null);
      expect(s.memTotalBytes, null);
      expect(s.diskTotalBytes, null);
      expect(s.cpuLoadPercent, null);
      expect(s.hasAnyData, true);
    });

    test('returns empty snapshot when markers absent', () {
      const raw = 'garbage output only';
      final s = parser.parse(raw);
      expect(s.hasAnyData, false);
    });

    test('handles no-swap systems', () {
      const raw = '''
---OPSPOCKET-HEALTH-BEGIN---
===MEM===
              total        used        free      shared  buff/cache   available
Mem:     1000000000   500000000   300000000     1048576   200000000   450000000
Swap:            0           0           0
---OPSPOCKET-HEALTH-END---
''';
      final s = parser.parse(raw);
      expect(s.memTotalBytes, 1000000000);
      expect(s.swapTotalBytes, 0);
    });
  });

  group('formatBytes', () {
    test('renders common sizes', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024), '1.00 KB');
      expect(formatBytes(1024 * 1024), '1.00 MB');
      expect(formatBytes(1024 * 1024 * 1024 * 2), '2.00 GB');
    });
    test('handles null', () {
      expect(formatBytes(null), '–');
    });
  });

  group('formatUptime', () {
    test('days/hours/minutes', () {
      expect(formatUptime(42), '0m');
      expect(formatUptime(120), '2m');
      expect(formatUptime(3700), '1h 1m');
      expect(formatUptime(90061), '1d 1h');
    });
    test('nulls', () {
      expect(formatUptime(null), '–');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:opspocket/app/core/utils/danger_detector.dart';

void main() {
  group('DangerDetector', () {
    test('flags rm -rf', () {
      expect(DangerDetector.isDangerous('rm -rf /etc/nginx'), isTrue);
      expect(DangerDetector.isDangerous('rm -fr /tmp/junk'), isTrue);
    });

    test('flags reboot/shutdown', () {
      expect(DangerDetector.isDangerous('sudo reboot'), isTrue);
      expect(DangerDetector.isDangerous('shutdown -h now'), isTrue);
      expect(DangerDetector.isDangerous('poweroff'), isTrue);
    });

    test('flags destructive disk ops', () {
      expect(DangerDetector.isDangerous('mkfs.ext4 /dev/sda1'), isTrue);
      expect(DangerDetector.isDangerous('dd if=/dev/zero of=/dev/sda'), isTrue);
    });

    test('flags docker system prune', () {
      expect(DangerDetector.isDangerous('docker system prune -a'), isTrue);
    });

    test('flags fork bombs', () {
      expect(DangerDetector.isDangerous(':(){ :|:& };:'), isTrue);
    });

    test('does not flag benign commands', () {
      expect(DangerDetector.isDangerous('ls -la'), isFalse);
      expect(DangerDetector.isDangerous('docker ps'), isFalse);
      expect(DangerDetector.isDangerous('journalctl -u nginx -n 50 --no-pager'), isFalse);
      expect(DangerDetector.isDangerous('systemctl status bot --no-pager'), isFalse);
    });

    test('reason is human-readable for matches', () {
      final r = DangerDetector.reason('sudo reboot');
      expect(r, isNotNull);
      expect(r, contains('destructive'));
    });

    test('reason is null for benign', () {
      expect(DangerDetector.reason('echo hi'), isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:opspocket/app/core/utils/sanitizer.dart';

void main() {
  group('Sanitizer', () {
    test('redacts DigitalOcean tokens', () {
      final s = Sanitizer.sanitize(
        'Using token dop_v1_0123456789abcdef0123456789abcdef0123456789abcdef',
      );
      expect(s, isNot(contains('dop_v1_0123')));
      expect(s, contains('[REDACTED]'));
    });

    test('redacts bearer auth headers', () {
      final s = Sanitizer.sanitize('Authorization: Bearer abc.def.ghi');
      expect(s, contains('[REDACTED]'));
      expect(s, isNot(contains('abc.def.ghi')));
    });

    test('redacts api_key assignments', () {
      final s = Sanitizer.sanitize('api_key=secret123');
      expect(s, contains('[REDACTED]'));
    });

    test('redacts OpenSSH private key blocks', () {
      const block = '''-----BEGIN OPENSSH PRIVATE KEY-----
abc
def
-----END OPENSSH PRIVATE KEY-----''';
      expect(Sanitizer.sanitize('before\n$block\nafter'), isNot(contains('abc')));
    });

    test('redacts AWS access key and gh_ tokens', () {
      final s = Sanitizer.sanitize('AKIAABCDEFGHIJKLMNOP ghp_abcdefghijklmnop1234');
      expect(s, isNot(contains('AKIAA')));
      expect(s, isNot(contains('ghp_abcdef')));
    });

    test('summarise truncates with suffix', () {
      final s = Sanitizer.summarise('x' * 2000, maxChars: 100);
      expect(s.length, lessThanOrEqualTo(130));
      expect(s, endsWith('[truncated]'));
    });
  });
}

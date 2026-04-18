import 'package:flutter_test/flutter_test.dart';
import 'package:opspocket/app/core/utils/placeholder_utils.dart';

void main() {
  group('PlaceholderUtils.extract', () {
    test('returns ordered unique placeholders', () {
      final out = PlaceholderUtils.extract('tail -n {{line_count}} {{log_path}}');
      expect(out, ['line_count', 'log_path']);
    });

    test('dedupes repeated placeholders', () {
      final out = PlaceholderUtils.extract('echo {{a}} {{a}} {{b}}');
      expect(out, ['a', 'b']);
    });

    test('tolerates whitespace in braces', () {
      final out = PlaceholderUtils.extract('systemctl restart {{ service_name }}');
      expect(out, ['service_name']);
    });

    test('returns empty for no placeholders', () {
      expect(PlaceholderUtils.extract('docker ps'), isEmpty);
    });
  });

  group('PlaceholderUtils.substitute', () {
    test('replaces provided values', () {
      final out = PlaceholderUtils.substitute(
        'tail -n {{line_count}} {{log_path}}',
        {'line_count': '50', 'log_path': '/var/log/app.log'},
      );
      expect(out, 'tail -n 50 /var/log/app.log');
    });

    test('leaves missing placeholders intact', () {
      final out = PlaceholderUtils.substitute(
        'echo {{a}} {{b}}',
        {'a': 'hello'},
      );
      expect(out, 'echo hello {{b}}');
    });
  });

  group('PlaceholderUtils.missing', () {
    test('reports absent keys', () {
      final out = PlaceholderUtils.missing('echo {{a}} {{b}}', {'a': 'x'});
      expect(out, ['b']);
    });

    test('reports empty-string keys as missing', () {
      final out = PlaceholderUtils.missing('echo {{a}}', {'a': ''});
      expect(out, ['a']);
    });
  });

  test('hasUnresolved detects leftover tokens', () {
    expect(PlaceholderUtils.hasUnresolved('echo {{a}}'), isTrue);
    expect(PlaceholderUtils.hasUnresolved('echo hello'), isFalse);
  });
}

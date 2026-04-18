import 'package:flutter_test/flutter_test.dart';
import 'package:opspocket/features/command_templates/data/builtin_templates.dart';

void main() {
  group('BuiltinTemplates', () {
    test('has no duplicate ids', () {
      final ts = BuiltinTemplates.all(DateTime(2026));
      final ids = ts.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every template is marked built-in', () {
      final ts = BuiltinTemplates.all(DateTime(2026));
      for (final t in ts) {
        expect(t.isBuiltin, isTrue, reason: '${t.id} missing isBuiltin');
      }
    });

    test('restart/reboot commands are flagged dangerous', () {
      final ts = BuiltinTemplates.all(DateTime(2026));
      final reboot = ts.firstWhere((t) => t.id == 'builtin.server.reboot');
      expect(reboot.dangerous, isTrue);

      final restartSvc = ts.firstWhere((t) => t.id == 'builtin.systemd.restart');
      expect(restartSvc.dangerous, isTrue);
    });

    test('log tail templates have line_count placeholder', () {
      final ts = BuiltinTemplates.all(DateTime(2026));
      final tail = ts.firstWhere((t) => t.id == 'builtin.file.tail');
      expect(tail.placeholders, containsAll(['line_count', 'log_path']));
    });

    test('slash shorthand renders correctly', () {
      final ts = BuiltinTemplates.all(DateTime(2026));
      final status = ts.firstWhere((t) => t.id == 'builtin.generic.status');
      expect(status.slash.startsWith('/'), isTrue);
    });
  });
}

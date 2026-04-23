import 'package:flutter_test/flutter_test.dart';
import 'package:opspocket/features/files/domain/sftp_browser_state.dart';

void main() {
  group('normalizeSftpPath', () {
    test('collapses duplicate slashes', () {
      expect(normalizeSftpPath('/home//user///logs'), '/home/user/logs');
    });
    test('resolves ..', () {
      expect(normalizeSftpPath('/home/user/../other'), '/home/other');
      expect(normalizeSftpPath('/a/b/c/../../d'), '/a/d');
    });
    test('cannot escape root', () {
      expect(normalizeSftpPath('/../../foo'), '/foo');
    });
    test('empty returns root', () {
      expect(normalizeSftpPath(''), '/');
    });
    test('preserves trailing file name', () {
      expect(normalizeSftpPath('/var/log/syslog'), '/var/log/syslog');
    });
    test('resolves dot', () {
      expect(normalizeSftpPath('/a/./b'), '/a/b');
    });
  });

  group('parentOf', () {
    test('root stays root', () {
      expect(parentOf('/'), '/');
    });
    test('single-level returns root', () {
      expect(parentOf('/home'), '/');
    });
    test('deeper path', () {
      expect(parentOf('/home/user/logs'), '/home/user');
    });
  });

  group('breadcrumbsFor', () {
    test('root is single entry', () {
      final bc = breadcrumbsFor('/');
      expect(bc.length, 1);
      expect(bc.first.label, '/');
    });
    test('deep path chained', () {
      final bc = breadcrumbsFor('/home/clawd/logs');
      expect(bc.length, 4);
      expect(bc[0].path, '/');
      expect(bc[1].label, 'home');
      expect(bc[1].path, '/home');
      expect(bc[2].label, 'clawd');
      expect(bc[2].path, '/home/clawd');
      expect(bc[3].label, 'logs');
      expect(bc[3].path, '/home/clawd/logs');
    });
  });
}

import 'package:appstore_dashboard/api/asc_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const body = 'MIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQg0123456789abcdefghijklmnopqrstuvwxyz';

  test('a PEM flattened to one line is rebuilt with BEGIN/END on their own lines', () {
    final out = normalizePem('-----BEGIN PRIVATE KEY-----$body-----END PRIVATE KEY-----');
    final lines = out.trim().split('\n');
    expect(lines.first, '-----BEGIN PRIVATE KEY-----');
    expect(lines.last, '-----END PRIVATE KEY-----');
    expect(lines.sublist(1, lines.length - 1).join(), body);
    expect(lines.sublist(1, lines.length - 1).every((l) => l.length <= 64), isTrue);
  });

  test('extra whitespace and surrounding text are dropped', () {
    final out = normalizePem('  junk\n-----BEGIN PRIVATE KEY-----\n  $body  \n\n-----END PRIVATE KEY-----\ntrailing');
    expect(out.contains('junk'), isFalse);
    expect(out.contains('trailing'), isFalse);
    expect(out.replaceAll(RegExp(r'-----[A-Z ]+-----|\s'), ''), body);
  });

  test('input without markers is only trimmed', () {
    expect(normalizePem('  not a key  '), 'not a key');
  });
}

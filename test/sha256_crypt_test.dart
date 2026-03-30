import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/utils/sha256_crypt.dart';

void main() {
  group('SHA-256 crypt', () {
    test('matches passlib reference (real router password)', () {
      final result = Sha256Crypt.hash('346500aB346500.', '4a3TeYc8dfZKDgMl');
      expect(
        result,
        r'$5$4a3TeYc8dfZKDgMl$M5cIwFEe4soMp7zbeFeBdGkRM4y5yO8BXlsbplckec2',
      );
    });

    test('matches passlib reference (simple password)', () {
      final result = Sha256Crypt.hash('password', 'saltsalt');
      expect(
        result,
        r'$5$saltsalt$gOjOtoMpVhru2uyjeJSEc/JaLQWOXMNmlOnj6T4AtC.',
      );
    });

    test('handles empty password', () {
      final result = Sha256Crypt.hash('', 'saltsalt');
      expect(
        result,
        r'$5$saltsalt$09agN5RZ2meWdEdnEusqsq5G7RwwghB8jCKoWWADxW/',
      );
    });

    test('handles empty salt', () {
      final result = Sha256Crypt.hash('hello', '');
      expect(result, r'$5$$TCRu/ts4Npu8OJyeWy2WnUHCe/6bKVMSi0sROUrPh48');
    });

    test('handles unicode/cyrillic password', () {
      final result = Sha256Crypt.hash('пароль', 'unicodesalt');
      expect(
        result,
        r'$5$unicodesalt$riyyEUYDotSBkjhNosGTPN2fVsc.DjGpwLFwGIMgMd.',
      );
    });

    test('handles special characters in salt', () {
      final result = Sha256Crypt.hash('test.pass!', 'a/b.c');
      expect(result, r'$5$a/b.c$vee/XycLMvVg2OU6SHvkoH15sT4kjI6CDsYGnju0W83');
    });

    test('rounds omitted when default (5000)', () {
      final result = Sha256Crypt.hash('test', 'saltsalt');
      expect(result.contains('rounds='), isFalse);
      expect(result.startsWith(r'$5$saltsalt$'), isTrue);
    });

    test('rounds included when non-default', () {
      final result = Sha256Crypt.hash('test', 'roundstest', rounds: 1000);
      expect(
        result,
        r'$5$rounds=1000$roundstest$Jiw5psqD9nmIaRRyp0o3qJZ7KwsvqJtCNaU8M/3GXxC',
      );
    });
  });
}

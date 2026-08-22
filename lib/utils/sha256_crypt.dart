import 'dart:typed_data';
import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;

/// Unix SHA-256 crypt implementation compatible with glibc/passlib.
/// Produces output in format `$5$salt$hash` (rounds=5000 is default, omitted).
///
/// Reference: https://www.akkadia.org/dreez/SHA-crypt.txt
class Sha256Crypt {
  static const _b64Chars =
      './0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

  static const _transpose = [
    20,
    10,
    0,
    11,
    1,
    21,
    2,
    22,
    12,
    23,
    13,
    3,
    14,
    4,
    24,
    5,
    25,
    15,
    26,
    16,
    6,
    17,
    7,
    27,
    8,
    28,
    18,
    29,
    19,
    9,
    30,
    31,
  ];

  static Uint8List _sha256(List<int> data) =>
      Uint8List.fromList(crypto.sha256.convert(data).bytes);

  static String hash(String password, String salt, {int rounds = 5000}) {
    final pw = utf8.encode(password);
    final normalizedSalt = salt.length > 16 ? salt.substring(0, 16) : salt;
    final s = utf8.encode(normalizedSalt);

    // Digest B
    final db = _sha256([...pw, ...s, ...pw]);

    // Digest A
    final aInput = <int>[...pw, ...s, ..._repeatBytes(db, pw.length)];
    var i = pw.length;
    while (i > 0) {
      aInput.addAll(i & 1 != 0 ? db : pw);
      i >>= 1;
    }
    final da = _sha256(aInput);

    // P-string
    final dpInput = <int>[];
    for (var j = 0; j < pw.length; j++) {
      dpInput.addAll(pw);
    }
    final dp = _repeatBytes(_sha256(dpInput), pw.length);

    // S-string
    final dsInput = <int>[];
    for (var j = 0; j < 16 + da[0]; j++) {
      dsInput.addAll(s);
    }
    final ds = _sha256(dsInput).sublist(0, s.length);

    // Rounds
    var c = Uint8List.fromList(da);
    for (var r = 0; r < rounds; r++) {
      final input = <int>[];
      input.addAll(r & 1 != 0 ? dp : c);
      if (r % 3 != 0) input.addAll(ds);
      if (r % 7 != 0) input.addAll(dp);
      input.addAll(r & 1 != 0 ? c : dp);
      c = _sha256(input);
    }

    // Base64 encode with transposition
    final sb = StringBuffer();
    for (var g = 0; g < 10; g++) {
      final idx = g * 3;
      _b64Encode(
        sb,
        c[_transpose[idx + 2]],
        c[_transpose[idx + 1]],
        c[_transpose[idx]],
        4,
      );
    }
    _b64Encode(sb, 0, c[_transpose[31]], c[_transpose[30]], 3);

    final roundsPrefix = rounds == 5000 ? '' : 'rounds=$rounds\$';
    return '\$5\$$roundsPrefix$normalizedSalt\$$sb';
  }

  static void _b64Encode(StringBuffer sb, int a, int b, int c, int n) {
    var w = (a << 16) | (b << 8) | c;
    for (var i = 0; i < n; i++) {
      sb.write(_b64Chars[w & 0x3F]);
      w >>= 6;
    }
  }

  static Uint8List _repeatBytes(Uint8List data, int length) {
    if (data.length >= length) {
      return Uint8List.fromList(data.sublist(0, length));
    }
    final result = Uint8List(length);
    var offset = 0;
    while (offset < length) {
      final copy = (data.length < length - offset)
          ? data.length
          : length - offset;
      result.setRange(offset, offset + copy, data);
      offset += copy;
    }
    return result;
  }
}

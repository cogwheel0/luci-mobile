import 'package:flutter/services.dart';

/// The keyboard for an IP address or a port range: digits, with `.` and `-`.
///
/// Plain [TextInputType.number] is iOS's number pad, which has digits and
/// nothing else, so an address or a range could not be typed at all. Signed
/// and decimal make it the numbers-and-punctuation keyboard on iOS, and add
/// the `-` and `.` keys to Android's number pad.
const numericAddressKeyboard = TextInputType.numberWithOptions(
  signed: true,
  decimal: true,
);

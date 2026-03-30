/// Format GL.iNet/UCI band string to human-readable label.
String formatWifiBand(String band) {
  switch (band.toLowerCase()) {
    case '2g':
    case '2.4g':
      return '2.4 GHz';
    case '5g':
      return '5 GHz';
    case '6g':
      return '6 GHz';
    default:
      return '';
  }
}

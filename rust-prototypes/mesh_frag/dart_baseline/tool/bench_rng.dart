import '../lib/core/crypto/keys.dart';

void main(List<String> args) {
  final iters = args.isEmpty ? 128000 : int.parse(args[0]);
  var acc = 0;
  final sw = Stopwatch()..start();
  for (var i = 0; i < iters; i++) {
    final b = randomBytes(8);
    acc += b[0];
  }
  sw.stop();
  final ms = sw.elapsedMicroseconds / 1000.0;
  print('iters=$iters randomBytes8: ${ms.toStringAsFixed(3)} ms, ${(ms * 1000 / iters).toStringAsFixed(2)} us/call, acc=$acc');
}

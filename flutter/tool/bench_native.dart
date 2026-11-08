import 'dart:io';
import 'dart:typed_data';

// The standalone baseline intentionally uses its own minimal dependencies.
// ignore: avoid_relative_lib_imports
import '../../rust-prototypes/mesh_frag/dart_baseline/lib/services/mesh/protocol/fragment_payload.dart';
import 'bench_native_impl.dart';

void main() {
  final data = Uint8List.fromList(List.generate(5000, (i) => i % 256));
  final id = Uint8List(8);
  const size = 450;
  const iterations = 50000;
  List<Uint8List> dartSplit() => [
    for (var i = 0; i < data.length; i += size)
      FragmentPayload(
        fragmentID: id,
        index: i ~/ size,
        total: (data.length + size - 1) ~/ size,
        originalType: 7,
        data: Uint8List.fromList(
          Uint8List.sublistView(
            data,
            i,
            i + size < data.length ? i + size : data.length,
          ),
        ),
      ).encode(),
  ];
  for (var i = 0; i < 5000; i++) {
    dartSplit();
    NativeFragment.split(data, id, size, 7);
  }
  final watch = Stopwatch()..start();
  var sum = 0;
  for (var i = 0; i < iterations; i++) {
    sum += dartSplit().length;
  }
  final d = watch.elapsedMicroseconds;
  watch.reset();
  for (var i = 0; i < iterations; i++) {
    sum += NativeFragment.split(data, id, size, 7)!.length;
  }
  stdout.writeln(
    'Dart ${d / iterations} us; FFI ${watch.elapsedMicroseconds / iterations} us; sum=$sum',
  );
}

import 'package:flutter_webrtc/flutter_webrtc.dart';

final _releasing = Expando<Future<void>>();
Future<void> releasePeerConnection(RTCPeerConnection pc) =>
    _releasing[pc] ??= _release(pc);
Future<void> _release(RTCPeerConnection pc) async {
  try {
    await pc.close();
  } catch (_) {}
  try {
    await pc.dispose();
  } catch (_) {}
}

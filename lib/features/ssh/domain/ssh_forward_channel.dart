import 'dart:async';
import 'dart:typed_data';

/// A bidirectional byte channel representing an SSH port-forward connection.
/// Returned by [SshClient.forwardChannel] so callers never import dartssh2.
class SshForwardChannel {
  /// Bytes arriving from the remote host.
  final Stream<Uint8List> stream;

  /// Sink for sending bytes to the remote host.
  final StreamSink<List<int>> sink;

  const SshForwardChannel({required this.stream, required this.sink});
}

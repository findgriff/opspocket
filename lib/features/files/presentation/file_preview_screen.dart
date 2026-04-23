import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_theme.dart';

/// In-app previewer for files fetched via SFTP. Text files render with the
/// terminal font; anything binary shows a hex dump header + byte count.
class FilePreviewScreen extends StatelessWidget {
  final String path;
  final Uint8List bytes;

  const FilePreviewScreen({super.key, required this.path, required this.bytes});

  String get _filename {
    final slash = path.lastIndexOf('/');
    return slash >= 0 ? path.substring(slash + 1) : path;
  }

  _DecodedPreview _decode() {
    if (_looksBinary(bytes)) {
      return _DecodedPreview.binary(bytes);
    }
    try {
      final text = utf8.decode(bytes, allowMalformed: false);
      return _DecodedPreview.text(text);
    } catch (_) {
      try {
        final text = latin1.decode(bytes);
        return _DecodedPreview.text(text);
      } catch (_) {
        return _DecodedPreview.binary(bytes);
      }
    }
  }

  /// Heuristic — any NUL byte in the first 4 KB suggests binary data.
  static bool _looksBinary(Uint8List b) {
    final limit = b.length < 4096 ? b.length : 4096;
    for (var i = 0; i < limit; i++) {
      if (b[i] == 0) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final decoded = _decode();
    return Scaffold(
      appBar: AppBar(
        title: Text(_filename, style: AppTheme.mono(size: 14)),
        actions: [
          if (decoded.isText)
            IconButton(
              icon: const Icon(Icons.copy_all_outlined),
              tooltip: 'Copy all',
              onPressed: () async {
                await Clipboard.setData(
                    ClipboardData(text: decoded.text ?? ''));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')));
              },
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              '$path  •  ${_sizeLabel(bytes.length)}'
              '${decoded.isText ? '  •  ${decoded.text!.split('\n').length} lines' : '  •  binary'}',
              style: AppTheme.mono(size: 11, color: AppTheme.muted),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: decoded.isText
                ? _TextBody(text: decoded.text!)
                : _BinaryBody(bytes: bytes),
          ),
        ],
      ),
    );
  }

  static String _sizeLabel(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

class _TextBody extends StatelessWidget {
  final String text;
  const _TextBody({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              text,
              style: AppTheme.mono(size: 12),
            ),
          ),
        ),
      ),
    );
  }
}

class _BinaryBody extends StatelessWidget {
  final Uint8List bytes;
  const _BinaryBody({required this.bytes});

  @override
  Widget build(BuildContext context) {
    // Show the first 512 bytes as hex — enough to identify file type visually.
    final limit = bytes.length < 512 ? bytes.length : 512;
    final buf = StringBuffer();
    for (var i = 0; i < limit; i += 16) {
      final end = (i + 16) < limit ? (i + 16) : limit;
      final row = bytes.sublist(i, end);
      buf.write(i.toRadixString(16).padLeft(8, '0'));
      buf.write('  ');
      for (var b in row) {
        buf.write(b.toRadixString(16).padLeft(2, '0'));
        buf.write(' ');
      }
      buf.write('\n');
    }

    return Container(
      color: Colors.black,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('Binary file — showing first $limit bytes',
                  style: AppTheme.mono(size: 11, color: AppTheme.warning)),
            ),
            const SizedBox(height: 10),
            SelectableText(
              buf.toString(),
              style: AppTheme.mono(size: 11, color: AppTheme.cyan),
            ),
          ],
        ),
      ),
    );
  }
}

/// Internal discriminated union for decoded content.
class _DecodedPreview {
  final String? text;
  final Uint8List? binary;
  const _DecodedPreview._(this.text, this.binary);
  factory _DecodedPreview.text(String t) => _DecodedPreview._(t, null);
  factory _DecodedPreview.binary(Uint8List b) => _DecodedPreview._(null, b);
  bool get isText => text != null;
}

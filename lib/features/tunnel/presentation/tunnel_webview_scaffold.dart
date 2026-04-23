import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Shared scaffolding for the tunnelled WebView screens (OpenClaw UI,
/// Mission Control). Responsibilities:
///
///   * Wire up a [WebViewController] with sensible defaults for the tunnel
///   * Show the orbital loading animation until the page is ready
///   * Handle `onWebResourceError` by swapping the loader for a retry card
///     so users can recover without backing out of the screen
///   * Allow landscape orientation while the screen is open, restoring the
///     app-wide portrait lock on dispose
///   * Provide an "Open in Safari" fallback for escape hatches
///
/// The two variants differ only in branding colour, title, logo asset and
/// status copy, so they are passed in as configuration.
class TunnelWebViewScaffold extends StatefulWidget {
  final String url;
  final String title;
  final Color accent;
  final String logoAsset;
  final List<String> statusMessages;

  const TunnelWebViewScaffold({
    super.key,
    required this.url,
    required this.title,
    required this.accent,
    required this.logoAsset,
    required this.statusMessages,
  });

  @override
  State<TunnelWebViewScaffold> createState() => _TunnelWebViewScaffoldState();
}

class _TunnelWebViewScaffoldState extends State<TunnelWebViewScaffold>
    with TickerProviderStateMixin {
  static const _bg = Color(0xFF000000);

  late final WebViewController _webController;
  late final AnimationController _orbitCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _revealCtrl;

  bool _webReady = false;
  bool _minTimeElapsed = false;
  int _statusIndex = 0;

  /// Last main-frame error (non-null means show the retry card).
  WebResourceError? _loadError;

  @override
  void initState() {
    super.initState();

    // Allow landscape while tunnelled content is visible — Mission Control
    // and OpenClaw dashboards are genuinely easier to use in landscape on
    // the phone. Reverted on dispose so the rest of the app stays portrait.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _orbitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    _revealCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      _minTimeElapsed = true;
      _maybeReveal();
    });

    _cycleStatus();
    _buildController();
  }

  void _buildController() {
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(_bg)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (!mounted) return;
          // Reaching onPageFinished cancels any earlier in-flight error.
          setState(() => _loadError = null);
          _onWebReady();
        },
        onWebResourceError: (error) {
          if (!mounted) return;
          // We only care about errors that block the main document —
          // subresource errors (favicons, fonts) shouldn't yank the user
          // back to a failure screen.
          final isMain = error.isForMainFrame ?? true;
          if (!isMain) return;
          setState(() {
            _loadError = error;
            _webReady = false;
          });
        },
      ),)
      ..loadRequest(Uri.parse(widget.url));
  }

  void _cycleStatus() {
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted || _revealCtrl.isAnimating || _revealCtrl.isCompleted) return;
      setState(() => _statusIndex =
          (_statusIndex + 1) % widget.statusMessages.length,);
      _cycleStatus();
    });
  }

  void _onWebReady() {
    if (_webReady) return;
    _webReady = true;
    _maybeReveal();
  }

  void _maybeReveal() {
    if (_webReady &&
        _minTimeElapsed &&
        !_revealCtrl.isAnimating &&
        !_revealCtrl.isCompleted) {
      setState(() {});
      _revealCtrl.forward();
    }
  }

  Future<void> _retry() async {
    setState(() {
      _loadError = null;
      _webReady = false;
    });
    // Rewind the reveal so the loader fades back in if it had already
    // completed on a prior successful load.
    _revealCtrl.value = 0;
    try {
      await _webController.loadRequest(Uri.parse(widget.url));
    } catch (_) {
      // loadRequest shouldn't throw in practice; if it does the error
      // callback will surface whatever went wrong.
    }
  }

  Future<void> _openInSafari() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() {
    // Restore the app-wide orientation lock (portrait-only) so leaving this
    // screen doesn't leave the rest of the app rotating.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    _orbitCtrl.dispose();
    _pulseCtrl.dispose();
    _revealCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // ── WebView (invisible until ready) ─────────────────────────────
          FadeTransition(
            opacity: _revealCtrl,
            child: Column(
              children: [
                _appBar(context),
                Expanded(child: WebViewWidget(controller: _webController)),
              ],
            ),
          ),

          // ── Loading / error overlay ──────────────────────────────────────
          //
          // The overlay covers the (still-loading) WebView until we either
          // reveal it (fade to transparent) or an error arrives. When an
          // error is set we force the overlay fully opaque even after a
          // previously-successful reveal, so the user always sees the retry
          // card on reload failures.
          AnimatedBuilder(
            animation: _revealCtrl,
            builder: (_, child) {
              final hasError = _loadError != null;
              final opacity = hasError ? 1.0 : (1.0 - _revealCtrl.value);
              return Opacity(
                opacity: opacity,
                child: IgnorePointer(
                  ignoring: !hasError && _revealCtrl.isCompleted,
                  child: child,
                ),
              );
            },
            child: _loadError != null
                ? _buildErrorOverlay(_loadError!)
                : _buildLoadingOverlay(),
          ),
        ],
      ),
    );
  }

  // ── App bar ────────────────────────────────────────────────────────────

  Widget _appBar(BuildContext context) {
    return Container(
      color: _bg,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFF2A2A2A))),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 4),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _webReady ? widget.accent : widget.accent.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: widget.accent
                          .withValues(alpha: _webReady ? 0.5 : 0.2),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                widget.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // External Safari handoff — always available so users can
              // escape to system Safari (copy link, inspect, share).
              IconButton(
                icon: const Icon(
                  Icons.open_in_browser,
                  size: 20,
                  color: Colors.white,
                ),
                tooltip: 'Open in Safari',
                onPressed: _openInSafari,
              ),
              if (_webReady)
                IconButton(
                  icon: const Icon(Icons.refresh,
                      size: 20, color: Colors.white,),
                  onPressed: () => _webController.reload(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Error overlay ──────────────────────────────────────────────────────

  Widget _buildErrorOverlay(WebResourceError error) {
    final accent = widget.accent;
    final message = _friendlyError(error);
    return Container(
      color: _bg,
      child: Column(
        children: [
          _appBar(context),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.error_outline,
                        size: 48, color: accent.withValues(alpha: 0.85),),
                    const SizedBox(height: 18),
                    Text(
                      'Couldn\u2019t load ${widget.title}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF999999),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent.withValues(alpha: 0.18),
                        foregroundColor: accent,
                        elevation: 0,
                        side: BorderSide(
                            color: accent.withValues(alpha: 0.5),),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text(
                        'Retry',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, letterSpacing: 0.3,),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF3A3A3A)),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _openInSafari,
                      icon: const Icon(Icons.open_in_browser, size: 18),
                      label: const Text(
                        'Open in Safari',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Turns low-level WebResourceError codes into something a human can read.
  String _friendlyError(WebResourceError e) {
    final desc = e.description.trim();
    final url = e.url;
    final hint = switch (e.errorCode) {
      -1004 || -1001 || -1005 =>
        'The service on the VPS isn\u2019t responding. Check it\u2019s running, then retry.',
      -999 => 'Load cancelled.',
      _ => desc.isEmpty ? 'Unknown error' : desc,
    };
    if (url != null && url.isNotEmpty) {
      return '$hint\n\n$url';
    }
    return hint;
  }

  // ── Loading overlay (orbital animation) ────────────────────────────────

  Widget _buildLoadingOverlay() {
    final accent = widget.accent;
    return Container(
      color: _bg,
      child: Column(
        children: [
          _appBar(context),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 260,
                    height: 260,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        _PulseRing(
                          controller: _pulseCtrl,
                          radius: 120,
                          color: accent,
                          phaseOffset: 0.0,
                        ),
                        _PulseRing(
                          controller: _pulseCtrl,
                          radius: 100,
                          color: accent,
                          phaseOffset: 0.33,
                        ),
                        _PulseRing(
                          controller: _pulseCtrl,
                          radius: 80,
                          color: accent,
                          phaseOffset: 0.66,
                        ),
                        AnimatedBuilder(
                          animation: _orbitCtrl,
                          builder: (_, __) => Transform.rotate(
                            angle: _orbitCtrl.value * 2 * math.pi,
                            child: CustomPaint(
                              size: const Size(240, 240),
                              painter: _ArcPainter(color: accent),
                            ),
                          ),
                        ),
                        Image.asset(
                          widget.logoAsset,
                          width: 140,
                          height: 140,
                          fit: BoxFit.contain,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: Text(
                      widget.statusMessages[_statusIndex],
                      key: ValueKey(_statusIndex),
                      style: const TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 13,
                        color: Color(0xFF888888),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: 200,
                    child: AnimatedBuilder(
                      animation: _orbitCtrl,
                      builder: (_, __) => ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: null,
                          backgroundColor: const Color(0xFF1A1A1A),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            accent.withValues(alpha: 0.8),
                          ),
                          minHeight: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pulsing ring ─────────────────────────────────────────────────────────────

class _PulseRing extends StatelessWidget {
  final AnimationController controller;
  final double radius;
  final Color color;
  final double phaseOffset;

  const _PulseRing({
    required this.controller,
    required this.radius,
    required this.color,
    required this.phaseOffset,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t = ((controller.value + phaseOffset) % 1.0);
        final scale = 0.6 + t * 0.6;
        final opacity = (1.0 - t).clamp(0.0, 1.0);
        return Transform.scale(
          scale: scale,
          child: Container(
            width: radius * 2,
            height: radius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withValues(alpha: opacity * 0.5),
                width: 1.5,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Sweep arc painter ────────────────────────────────────────────────────────

class _ArcPainter extends CustomPainter {
  final Color color;
  const _ArcPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [color.withValues(alpha: 0.0), color],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0,
      math.pi * 1.5,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) => false;
}

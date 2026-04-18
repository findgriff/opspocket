import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

// Brand colours
const _red = Color(0xFFFF3B1F);
const _cyan = Color(0xFF00E6FF);
const _bg = Color(0xFF000000);

class MissionControlScreen extends StatefulWidget {
  final String url;
  const MissionControlScreen({super.key, required this.url});

  @override
  State<MissionControlScreen> createState() => _MissionControlScreenState();
}

class _MissionControlScreenState extends State<MissionControlScreen>
    with TickerProviderStateMixin {
  late final WebViewController _webController;
  late final AnimationController _orbitCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _revealCtrl;

  bool _webReady = false;
  bool _minTimeElapsed = false;
  int _statusIndex = 0;

  static const _statusMessages = [
    'Establishing SSH tunnel…',
    'Handshaking with VPS…',
    'Routing to Mission Control…',
    'Loading interface…',
  ];

  @override
  void initState() {
    super.initState();

    // Orbit ring — continuous rotation
    _orbitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    // Pulse rings — continuous in/out
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    // Reveal overlay — plays once when web is ready
    _revealCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // Minimum 3-second animation display
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      _minTimeElapsed = true;
      _maybeReveal();
    });

    // Cycle status text every 1.4 s
    _cycleStatus();

    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(_bg)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => _onWebReady(),
        onWebResourceError: (_) => _onWebReady(), // reveal even on error
      ),)
      ..loadRequest(Uri.parse(widget.url));
  }

  void _cycleStatus() {
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted || _revealCtrl.isAnimating || _revealCtrl.isCompleted) return;
      setState(() => _statusIndex =
          (_statusIndex + 1) % _statusMessages.length,);
      _cycleStatus();
    });
  }

  void _onWebReady() {
    if (_webReady) return;
    _webReady = true;
    _maybeReveal();
  }

  void _maybeReveal() {
    if (_webReady && _minTimeElapsed && !_revealCtrl.isAnimating && !_revealCtrl.isCompleted) {
      setState(() {});
      _revealCtrl.forward();
    }
  }

  @override
  void dispose() {
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

          // ── Loading overlay ──────────────────────────────────────────────
          AnimatedBuilder(
            animation: _revealCtrl,
            builder: (_, child) => Opacity(
              opacity: 1.0 - _revealCtrl.value,
              child: IgnorePointer(
                ignoring: _revealCtrl.isCompleted,
                child: child,
              ),
            ),
            child: _buildLoadingOverlay(),
          ),
        ],
      ),
    );
  }

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
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: _webReady ? _cyan : _red,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(
                    color: (_webReady ? _cyan : _red).withValues(alpha: 0.5),
                    blurRadius: 6,
                  ),],
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Mission Control',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (_webReady)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20, color: Colors.white),
                  onPressed: () => _webController.reload(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
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
                  // ── Animated logo + rings ──────────────────────────────────
                  SizedBox(
                    width: 260,
                    height: 260,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Outer pulse ring
                        _PulseRing(
                          controller: _pulseCtrl,
                          radius: 120,
                          color: _red,
                          phaseOffset: 0.0,
                        ),
                        // Middle pulse ring
                        _PulseRing(
                          controller: _pulseCtrl,
                          radius: 100,
                          color: _red,
                          phaseOffset: 0.33,
                        ),
                        // Inner pulse ring
                        _PulseRing(
                          controller: _pulseCtrl,
                          radius: 80,
                          color: _red,
                          phaseOffset: 0.66,
                        ),
                        // Rotating arc
                        AnimatedBuilder(
                          animation: _orbitCtrl,
                          builder: (_, __) => Transform.rotate(
                            angle: _orbitCtrl.value * 2 * math.pi,
                            child: const CustomPaint(
                              size: Size(240, 240),
                              painter: _ArcPainter(color: _red),
                            ),
                          ),
                        ),
                        // Logo
                        Image.asset(
                          'assets/mission_control_logo.png',
                          width: 140,
                          height: 140,
                          fit: BoxFit.contain,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // ── Status text ────────────────────────────────────────────
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: Text(
                      _statusMessages[_statusIndex],
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

                  // ── Scanning bar ───────────────────────────────────────────
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
                            _red.withValues(alpha: 0.8),
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

// ── Pulsing ring painter ──────────────────────────────────────────────────────

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

// ── Rotating arc painter ──────────────────────────────────────────────────────

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
      math.pi * 1.5, // 270° arc
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) => false;
}

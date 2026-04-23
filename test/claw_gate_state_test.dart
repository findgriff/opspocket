import 'package:flutter_test/flutter_test.dart';
import 'package:opspocket/features/tunnel/domain/claw_gate_state.dart';

void main() {
  group('ClawGateState', () {
    test('idle default', () {
      const s = ClawGateState.idle();
      expect(s.status, ClawGateStatus.idle);
      expect(s.isActive, false);
      expect(s.isBusy, false);
      expect(s.tunnelUrl, isNull);
    });

    test('active clawbot exposes a tunnel URL with token fragment', () {
      const s = ClawGateState(
        status: ClawGateStatus.active,
        activeTarget: TunnelTarget.clawbot,
        localPort: 53421,
        token: 'abc123',
      );
      expect(s.isActive, true);
      expect(s.tunnelUrl, 'http://127.0.0.1:53421/#token=abc123');
    });

    test('active mission-control tunnels to OpenClaw root (2026.4.5)', () {
      // 2026-04-23 pivot: Mission Control and OpenClaw UI are the same
      // server-side app; missionControl no longer carves out a
      // legacy /mission-control nginx path.
      const s = ClawGateState(
        status: ClawGateStatus.active,
        activeTarget: TunnelTarget.missionControl,
        localPort: 53421,
      );
      expect(s.tunnelUrl, 'http://127.0.0.1:53421/');
    });

    test('active without token uses plain root URL (basic-auth flow)', () {
      // gateway.auth.mode = "none" in 2026.4.5 → no token; WebView
      // surfaces the 401 basic-auth dialog.
      const s = ClawGateState(
        status: ClawGateStatus.active,
        activeTarget: TunnelTarget.clawbot,
        localPort: 53421,
      );
      expect(s.tunnelUrl, 'http://127.0.0.1:53421/');
    });

    test('fetchingToken is busy and not active', () {
      const s = ClawGateState(status: ClawGateStatus.fetchingToken);
      expect(s.isBusy, true);
      expect(s.isActive, false);
      expect(s.tunnelUrl, isNull);
    });

    test('error state surfaces message, no URL', () {
      const s = ClawGateState(
        status: ClawGateStatus.error,
        errorMessage: 'SSH not connected',
      );
      expect(s.tunnelUrl, isNull);
      expect(s.errorMessage, 'SSH not connected');
    });

    test('copyWith patches fields without losing others', () {
      const s = ClawGateState(
        status: ClawGateStatus.starting,
        activeTarget: TunnelTarget.clawbot,
      );
      final t = s.copyWith(
        status: ClawGateStatus.active,
        localPort: 1234,
        token: 'tok',
      );
      expect(t.status, ClawGateStatus.active);
      expect(t.activeTarget, TunnelTarget.clawbot);
      expect(t.localPort, 1234);
      expect(t.token, 'tok');
    });
  });

  group('TunnelTarget', () {
    test('remotePort — both targets hit the OpenClaw daemon on 18789', () {
      // 2026-04-23 pivot: Mission Control and OpenClaw UI are the same
      // server-side app; both tunnel to :18789.
      expect(TunnelTarget.clawbot.remotePort, 18789);
      expect(TunnelTarget.missionControl.remotePort, 18789);
    });

    test('labels are user-facing', () {
      expect(TunnelTarget.clawbot.label, 'OpenClaw UI');
      expect(TunnelTarget.missionControl.label, 'Mission Control');
    });
  });
}

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

    test('active mission-control exposes /mission-control path', () {
      const s = ClawGateState(
        status: ClawGateStatus.active,
        activeTarget: TunnelTarget.missionControl,
        localPort: 53421,
      );
      expect(s.tunnelUrl, 'http://127.0.0.1:53421/mission-control');
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
    test('remotePort matches design spec (18789 for clawbot)', () {
      expect(TunnelTarget.clawbot.remotePort, 18789);
      expect(TunnelTarget.missionControl.remotePort, 80);
    });

    test('labels are user-facing', () {
      expect(TunnelTarget.clawbot.label, 'OpenClaw UI');
      expect(TunnelTarget.missionControl.label, 'Mission Control');
    });
  });
}

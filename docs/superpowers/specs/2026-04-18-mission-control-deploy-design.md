# Mission Control One-Tap Deploy

**Date:** 2026-04-18  
**Status:** Approved

## Overview

A "Deploy Mission Control" button on the server detail screen that SSHes into the VPS and deploys the latest version of the Mission Control web app from GitHub — handling both first-time setup and subsequent updates automatically.

**Repo:** `git@github.com:findgriff/mission-control.git`  
**VPS path:** `/home/clawd/mission-control`  
**Port:** `3001`  
**pm2 name:** `mission-control`

---

## User Flow

1. User taps **Deploy Mission Control** tile on the server detail screen
2. `DeployScreen` opens fullscreen
3. Steps execute sequentially via SSH, each updating in real time:
   - **Check** — detect if `/home/clawd/mission-control` exists on VPS
   - **Clone or Pull** — `git clone` on first run, `git pull` on updates
   - **Install** — `npm install --omit=dev`
   - **Build** — `npm run build` (~60–90s)
   - **Start / Restart** — `pm2 restart mission-control` or `pm2 start "npm start -- --port 3001" --name mission-control`
   - **Save** — `pm2 save`
4. Each step shows a spinner → green tick (success) or red cross (failure)
5. Build step output is shown collapsed and expandable
6. On failure: error output shown + **Retry** button restarts from step 1
7. On success: **Open Mission Control** button navigates to MCScreen

---

## Architecture

### New Files

| File | Purpose |
|------|---------|
| `lib/features/mission_control/domain/deploy_state.dart` | `DeployStepStatus` enum, `DeployStep` model, `DeployState` aggregate |
| `lib/features/mission_control/presentation/deploy_notifier.dart` | `DeployNotifier extends StateNotifier<DeployState>` — drives the step sequence via SSH |
| `lib/features/mission_control/presentation/deploy_screen.dart` | Fullscreen deploy UI — step list, spinner, output, retry/open buttons |

### Modified Files

| File | Change |
|------|--------|
| `lib/features/server_profiles/presentation/server_detail_screen.dart` | Add `_DeployTile` below Mission Control tile |

---

## Domain: `deploy_state.dart`

```dart
enum DeployStepStatus { pending, running, success, failure }

class DeployStep {
  final String label;
  final DeployStepStatus status;
  final String output; // stdout/stderr from SSH exec
  const DeployStep({required this.label, this.status = DeployStepStatus.pending, this.output = ''});
  DeployStep copyWith({DeployStepStatus? status, String? output}) => ...;
}

class DeployState {
  final List<DeployStep> steps;
  final bool done;      // all steps succeeded
  final bool failed;    // a step failed
  final int activeStep; // index of currently-running step (-1 = not started)
}
```

Six steps (indices 0–5):
0. Checking VPS
1. Cloning / Pulling code
2. Installing packages
3. Building
4. Starting service
5. Saving pm2 state

---

## Notifier: `deploy_notifier.dart`

```dart
final deployProvider = StateNotifierProvider.autoDispose.family<
  DeployNotifier, DeployState, String
>((ref, serverId) => DeployNotifier(ref.read(sshClientProvider(serverId))));
```

`DeployNotifier.deploy()`:
1. Reset state, mark step 0 running
2. SSH exec: `test -d /home/clawd/mission-control && echo exists || echo missing`
   - Sets `_isFirstRun` flag
3. Step 1: clone or pull
   - First run: `cd /home/clawd && git clone git@github.com:findgriff/mission-control.git`
   - Update: `git -C /home/clawd/mission-control pull`
4. Step 2: `cd /home/clawd/mission-control && npm install --omit=dev`
5. Step 3: `cd /home/clawd/mission-control && npm run build`
6. Step 4: `cd /home/clawd/mission-control && (pm2 restart mission-control || pm2 start "npm start -- --port 3001" --name mission-control)`
7. Step 5: `pm2 save`
8. Mark `done = true`

On any step failure (non-zero exit or exception): mark step as `failure`, set `failed = true`, stop sequence.

All commands run as clawd: wrapped with `su - clawd -c '...'` consistent with McRepository pattern.

---

## UI: `deploy_screen.dart`

- Full-screen, `backgroundColor: Color(0xFF000000)`
- Header: close button + "DEPLOY" mono label + server name (same pattern as MCScreen header)
- Step list: each row shows icon (spinner/tick/cross), label, and output toggle
- Build step (index 3) shows a collapsible output box (monospace, scrollable, max 200 lines)
- Footer:
  - While running: nothing
  - On failure: red **Retry** button (calls `notifier.deploy()` again)
  - On success: green **Open Mission Control** button (pushes MCScreen)

---

## Server Detail Tile

```dart
_ActionTile(
  icon: Icons.rocket_launch_outlined,
  label: 'Deploy Mission Control',
  subtitle: 'Pull latest & rebuild from GitHub',
  color: Color(0xFFB57BFF), // purple
  onTap: () => Navigator.push(context, MaterialPageRoute(
    builder: (_) => DeployScreen(serverId: serverId, serverName: name),
    fullscreenDialog: true,
  )),
),
```

Placed directly below the existing Mission Control tile.

---

## Prerequisites (one-time manual setup)

The VPS `clawd` user needs a GitHub deploy key so `git clone/pull` works over SSH:

```bash
# On the VPS as clawd:
ssh-keygen -t ed25519 -C "clawd@vps" -f ~/.ssh/id_ed25519 -N ""
cat ~/.ssh/id_ed25519.pub
```

Add the printed public key to GitHub:  
**github.com/findgriff/mission-control → Settings → Deploy keys → Add deploy key** (read-only is sufficient).

Then test: `ssh -T git@github.com`

---

## Error Handling

| Scenario | Behaviour |
|----------|-----------|
| SSH not connected | Step 0 fails immediately with "SSH not connected" |
| git clone fails (no deploy key) | Step 1 fails, output shows SSH auth error |
| npm install fails | Step 2 fails, output shown |
| Build fails (TypeScript error etc.) | Step 3 fails, full build output shown in expandable box |
| pm2 not found | Step 4 fails with "pm2 not found — is OpenClaw installed?" |
| Any step timeout (>5 min) | Step marked failed with timeout message |

All failures show a **Retry** button.

---

## Out of Scope

- Nginx configuration (assumed already set up)
- Rollback to previous version
- Deploy key generation from within the app
- Multiple environment support

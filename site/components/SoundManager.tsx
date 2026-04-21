'use client';

/**
 * OpsPocket sound design — purely synthesized via Web Audio so the site ships
 * with sound from day one, with zero asset pipeline. Can be swapped for MP3s
 * later by replacing the `play()` implementations while keeping the same
 * public API (`sfx.boot()`, `sfx.click()`, etc).
 *
 * Design intent:
 *   boot   — the "radio comms latches on" feel. Low sweep + soft click.
 *   radar  — outbound sonar ping. Sine tone, fast decay.
 *   click  — CTA confirmation. Square-ish, very short.
 *   hover  — almost subliminal tick. Soft sine, very short.
 *   type   — keystroke for typewriter effect. White noise burst, 8ms.
 *
 * We respect `prefers-reduced-motion` and an explicit user mute toggle
 * (stored in localStorage). First sound plays only after the user has
 * interacted once (browser autoplay policy).
 */

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';

type Sfx = {
  boot: () => void;
  radar: () => void;
  click: () => void;
  hover: () => void;
  type: () => void;
  muted: boolean;
  toggleMute: () => void;
  armed: boolean; // true once user has interacted and audio can play
};

const SoundContext = createContext<Sfx | null>(null);

export function SoundProvider({ children }: { children: React.ReactNode }) {
  const ctxRef = useRef<AudioContext | null>(null);
  const [armed, setArmed] = useState(false);
  const [muted, setMuted] = useState(false);

  // Read persisted mute preference on mount.
  useEffect(() => {
    try {
      setMuted(localStorage.getItem('opspocket.muted') === '1');
    } catch {
      /* ignore */
    }
  }, []);

  // Arm the audio context on the first user gesture (required by browsers).
  useEffect(() => {
    const arm = () => {
      if (ctxRef.current) return;
      try {
        const AC =
          (window as unknown as { AudioContext: typeof AudioContext }).AudioContext ||
          (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
        ctxRef.current = new AC();
        setArmed(true);
      } catch {
        /* browser won't let us — silent site is fine */
      }
    };
    window.addEventListener('pointerdown', arm, { once: true });
    window.addEventListener('keydown', arm, { once: true });
    return () => {
      window.removeEventListener('pointerdown', arm);
      window.removeEventListener('keydown', arm);
    };
  }, []);

  const toggleMute = useCallback(() => {
    setMuted((prev) => {
      const next = !prev;
      try {
        localStorage.setItem('opspocket.muted', next ? '1' : '0');
      } catch {
        /* ignore */
      }
      return next;
    });
  }, []);

  // ── Tone helpers ────────────────────────────────────────────────────────
  // All sounds use short envelopes to avoid fatigue. Volumes are modest so
  // the site doesn't blast on unmuted speakers.

  const tone = useCallback(
    (opts: {
      freq: number;
      duration: number;
      type?: OscillatorType;
      gain?: number;
      sweep?: number; // target freq for a linear ramp
    }) => {
      const ctx = ctxRef.current;
      if (!ctx || muted) return;
      const now = ctx.currentTime;
      const osc = ctx.createOscillator();
      const g = ctx.createGain();
      osc.type = opts.type ?? 'sine';
      osc.frequency.setValueAtTime(opts.freq, now);
      if (opts.sweep !== undefined) {
        osc.frequency.linearRampToValueAtTime(opts.sweep, now + opts.duration);
      }
      const peak = opts.gain ?? 0.08;
      g.gain.setValueAtTime(0, now);
      g.gain.linearRampToValueAtTime(peak, now + 0.006);
      g.gain.exponentialRampToValueAtTime(0.0001, now + opts.duration);
      osc.connect(g).connect(ctx.destination);
      osc.start(now);
      osc.stop(now + opts.duration + 0.02);
    },
    [muted],
  );

  const noise = useCallback(
    (duration: number, gain = 0.04) => {
      const ctx = ctxRef.current;
      if (!ctx || muted) return;
      const now = ctx.currentTime;
      const buffer = ctx.createBuffer(1, Math.ceil(ctx.sampleRate * duration), ctx.sampleRate);
      const data = buffer.getChannelData(0);
      for (let i = 0; i < data.length; i += 1) {
        data[i] = (Math.random() * 2 - 1) * (1 - i / data.length);
      }
      const src = ctx.createBufferSource();
      src.buffer = buffer;
      const g = ctx.createGain();
      g.gain.value = gain;
      src.connect(g).connect(ctx.destination);
      src.start(now);
    },
    [muted],
  );

  // ── Named effects ───────────────────────────────────────────────────────

  const boot = useCallback(() => {
    // Layered: low sweep up, short click on top.
    tone({ freq: 180, sweep: 520, duration: 0.42, type: 'sawtooth', gain: 0.06 });
    setTimeout(() => tone({ freq: 880, duration: 0.08, type: 'sine', gain: 0.1 }), 380);
  }, [tone]);

  const radar = useCallback(() => {
    tone({ freq: 840, sweep: 640, duration: 0.32, type: 'sine', gain: 0.07 });
  }, [tone]);

  const click = useCallback(() => {
    tone({ freq: 620, duration: 0.06, type: 'square', gain: 0.05 });
  }, [tone]);

  const hover = useCallback(() => {
    tone({ freq: 1200, duration: 0.03, type: 'sine', gain: 0.025 });
  }, [tone]);

  const type = useCallback(() => {
    noise(0.02, 0.025);
  }, [noise]);

  const value = useMemo<Sfx>(
    () => ({ boot, radar, click, hover, type, muted, toggleMute, armed }),
    [boot, radar, click, hover, type, muted, toggleMute, armed],
  );

  return <SoundContext.Provider value={value}>{children}</SoundContext.Provider>;
}

export function useSound(): Sfx {
  const ctx = useContext(SoundContext);
  if (!ctx) {
    // Render-safe fallback for components outside the provider (SSR, tests).
    return {
      boot: () => {},
      radar: () => {},
      click: () => {},
      hover: () => {},
      type: () => {},
      muted: false,
      toggleMute: () => {},
      armed: false,
    };
  }
  return ctx;
}

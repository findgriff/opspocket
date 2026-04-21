'use client';

/**
 * BootSequence — the branded landing intro.
 *
 * Timeline (total ~2.2s before user can interact):
 *   0.00s  Black screen + CRT hum implied (scanlines on <body>)
 *   0.10s  Scanline sweep top → bottom (visual only)
 *   0.35s  Claw/target mark fades in center, scales 0.6 → 1.0
 *   0.55s  "boot" sound fires
 *   0.70s  First radar pulse emanates
 *   0.80s  Typewriter starts printing "OPSPOCKET // MISSION READY"
 *   1.90s  Hero copy + CTAs fade up from below
 *   2.20s  Handoff to idle state — radar continues looping every ~3s
 *
 * Respects `prefers-reduced-motion`: if the user opts out we skip the
 * animated intro and render the hero directly.
 */

import { motion, useReducedMotion } from 'framer-motion';
import { useEffect, useState } from 'react';
import { useSound } from './SoundManager';
import Typewriter from './Typewriter';

export default function BootSequence({ children }: { children: React.ReactNode }) {
  const reduced = useReducedMotion();
  const { boot, radar, armed } = useSound();
  const [step, setStep] = useState<'idle' | 'booted'>('idle');

  // Fire the boot sound + kick off the idle state.
  useEffect(() => {
    if (reduced) {
      setStep('booted');
      return;
    }
    const t1 = setTimeout(() => armed && boot(), 550);
    const t2 = setTimeout(() => armed && radar(), 720);
    const t3 = setTimeout(() => setStep('booted'), 2200);
    return () => {
      clearTimeout(t1);
      clearTimeout(t2);
      clearTimeout(t3);
    };
  }, [reduced, armed, boot, radar]);

  if (reduced) return <>{children}</>;

  return (
    <div className="relative">
      {/* Scanline sweep — single pass top to bottom */}
      <motion.div
        initial={{ y: '-100%', opacity: 0.9 }}
        animate={{ y: '120vh', opacity: 0 }}
        transition={{ duration: 1.0, ease: 'easeOut', delay: 0.1 }}
        className="pointer-events-none fixed inset-x-0 top-0 h-[3px] z-[100]"
        style={{
          background:
            'linear-gradient(to bottom, rgba(0,230,255,0) 0%, rgba(0,230,255,0.9) 50%, rgba(0,230,255,0) 100%)',
          boxShadow: '0 0 24px rgba(0, 230, 255, 0.55)',
        }}
      />

      {/* Centered claw materialising */}
      <motion.div
        initial={{ opacity: 0, scale: 0.6 }}
        animate={{ opacity: step === 'booted' ? 0 : 1, scale: 1 }}
        transition={{
          opacity: step === 'booted' ? { delay: 0.4, duration: 0.6 } : { delay: 0.35, duration: 0.4 },
          scale: { delay: 0.35, duration: 0.5, ease: 'easeOut' },
        }}
        className="pointer-events-none fixed inset-0 z-[90] flex items-center justify-center"
      >
        <ClawMark />
      </motion.div>

      {/* Boot caption that fades out */}
      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: step === 'booted' ? 0 : 1 }}
        transition={{
          opacity: step === 'booted' ? { delay: 0.2, duration: 0.5 } : { delay: 0.8 },
        }}
        className="pointer-events-none fixed inset-x-0 bottom-[22vh] z-[91] flex justify-center"
      >
        <div className="mono text-xs tracking-[0.3em] uppercase text-[var(--color-cyan)]/80">
          <Typewriter text="OPSPOCKET // MISSION READY" speed={55} startDelay={800} />
        </div>
      </motion.div>

      {/* Hero reveal */}
      <motion.div
        initial={{ opacity: 0, y: 18 }}
        animate={{
          opacity: step === 'booted' ? 1 : 0,
          y: step === 'booted' ? 0 : 18,
        }}
        transition={{ duration: 0.7, ease: 'easeOut', delay: step === 'booted' ? 0.15 : 0 }}
      >
        {children}
      </motion.div>
    </div>
  );
}

/** The stylised claw / target mark — pure SVG, no asset dependencies. */
function ClawMark() {
  return (
    <svg
      width="156"
      height="156"
      viewBox="0 0 156 156"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      className="drop-shadow-[0_0_32px_rgba(255,59,31,0.55)]"
    >
      {/* Outer ring */}
      <circle cx="78" cy="78" r="70" stroke="var(--color-red)" strokeWidth="1.5" opacity="0.4" />
      {/* Middle ring */}
      <circle cx="78" cy="78" r="52" stroke="var(--color-red)" strokeWidth="1" opacity="0.55" />
      {/* Inner filled disk */}
      <circle cx="78" cy="78" r="8" fill="var(--color-red)" />
      {/* Crosshair arms */}
      <line x1="78" y1="4" x2="78" y2="34" stroke="var(--color-red)" strokeWidth="1.5" />
      <line x1="78" y1="122" x2="78" y2="152" stroke="var(--color-red)" strokeWidth="1.5" />
      <line x1="4" y1="78" x2="34" y2="78" stroke="var(--color-red)" strokeWidth="1.5" />
      <line x1="122" y1="78" x2="152" y2="78" stroke="var(--color-red)" strokeWidth="1.5" />
      {/* Three "claw tips" */}
      <path
        d="M 78 22 L 68 42 L 78 36 L 88 42 Z"
        fill="var(--color-red)"
        opacity="0.85"
      />
    </svg>
  );
}

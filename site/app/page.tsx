'use client';

import Link from 'next/link';
import { motion } from 'framer-motion';
import BootSequence from '@/components/BootSequence';
import RadarPulse from '@/components/RadarPulse';
import Typewriter from '@/components/Typewriter';
import { useSound } from '@/components/SoundManager';

export default function Home() {
  const { hover, click } = useSound();

  return (
    <BootSequence>
      {/* ── Hero ─────────────────────────────────────────────────────────── */}
      <section className="relative min-h-[calc(100vh-56px)] flex items-center justify-center px-5 overflow-hidden">
        {/* Background radar pulse */}
        <div className="pointer-events-none absolute inset-0 flex items-center justify-center opacity-50">
          <RadarPulse size={10} sound />
        </div>

        {/* Grid backdrop */}
        <div
          className="pointer-events-none absolute inset-0 opacity-[0.04]"
          style={{
            backgroundImage:
              'linear-gradient(to right, white 1px, transparent 1px), linear-gradient(to bottom, white 1px, transparent 1px)',
            backgroundSize: '48px 48px',
          }}
        />

        <div className="relative max-w-3xl text-center">
          <p className="mono text-xs tracking-[0.4em] uppercase text-[var(--color-cyan)] mb-5">
            <Typewriter text="// MISSION READY" speed={35} startDelay={200} sound={false} />
          </p>

          <motion.h1
            initial={{ opacity: 0, y: 14 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.2 }}
            className="text-4xl sm:text-6xl font-bold leading-[1.05] tracking-tight"
          >
            The mobile command centre for{' '}
            <span className="text-[var(--color-red)]">AI agents</span>.
          </motion.h1>

          <motion.p
            initial={{ opacity: 0, y: 14 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.4 }}
            className="mt-5 text-base sm:text-lg text-[var(--color-muted)] max-w-xl mx-auto"
          >
            OpsPocket is a purpose-built iOS app for running, monitoring and
            operating AI agents — on your own VPS, or fully managed by us.
            SSH, MCP, and mission control from your pocket.
          </motion.p>

          <motion.div
            initial={{ opacity: 0, y: 14 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.6 }}
            className="mt-10 flex flex-col sm:flex-row gap-3 justify-center"
          >
            <Link
              href="/cloud"
              onMouseEnter={hover}
              onClick={click}
              className="btn btn-primary"
            >
              Try OpsPocket Cloud
              <span aria-hidden>→</span>
            </Link>
            <Link
              href="/app"
              onMouseEnter={hover}
              onClick={click}
              className="btn btn-ghost"
            >
              Get the App
            </Link>
          </motion.div>

          <motion.p
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ duration: 0.6, delay: 0.9 }}
            className="mono text-[11px] tracking-[0.3em] uppercase text-[var(--color-muted)] mt-10"
          >
            iPhone · iPad · No DevOps required
          </motion.p>
        </div>
      </section>

      {/* ── Three-up "what it does" ──────────────────────────────────────── */}
      <section className="max-w-6xl mx-auto px-5 py-20 border-t border-[var(--color-border)]">
        <div className="grid sm:grid-cols-3 gap-6">
          <Feature
            kicker="01 // APP"
            title="Fleet control, in your pocket"
            body="Connect any VPS via SSH or MCP. Dispatch tasks, tail logs, browse files — from the bus, the gym, anywhere."
          />
          <Feature
            kicker="02 // CLOUD"
            title="Managed. Zero DevOps."
            body="We provision, secure and maintain a dedicated OpenClaw instance for you. Subscribe; we deploy; you chat."
          />
          <Feature
            kicker="03 // TOGETHER"
            title="One coherent experience"
            body="App + Cloud sold together, priced with a bundle discount. Your team already uses it before they see a terminal."
          />
        </div>
      </section>

      {/* ── Pricing teaser ───────────────────────────────────────────────── */}
      <section className="max-w-6xl mx-auto px-5 py-20 border-t border-[var(--color-border)] text-center">
        <p className="mono text-xs tracking-[0.35em] uppercase text-[var(--color-cyan)] mb-4">
          // pricing
        </p>
        <h2 className="text-3xl sm:text-4xl font-bold">Four tiers. One tap to start.</h2>
        <p className="mt-4 text-[var(--color-muted)] max-w-xl mx-auto">
          From $9/mo for the app alone, up to $99/mo for Agency-grade managed
          infrastructure. Seven-day free trial on every plan.
        </p>
        <div className="mt-8">
          <Link
            href="/pricing"
            onMouseEnter={hover}
            onClick={click}
            className="btn btn-primary"
          >
            See the tiers
            <span aria-hidden>→</span>
          </Link>
        </div>
      </section>
    </BootSequence>
  );
}

function Feature({ kicker, title, body }: { kicker: string; title: string; body: string }) {
  return (
    <div className="border border-[var(--color-border)] bg-[var(--color-card)] rounded-xl p-6">
      <p className="mono text-[11px] tracking-[0.3em] uppercase text-[var(--color-red)]">
        {kicker}
      </p>
      <h3 className="mt-3 text-xl font-semibold">{title}</h3>
      <p className="mt-2 text-sm text-[var(--color-muted)] leading-relaxed">{body}</p>
    </div>
  );
}

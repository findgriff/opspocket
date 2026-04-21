'use client';

import Link from 'next/link';
import { motion } from 'framer-motion';
import { useSound } from '@/components/SoundManager';
import RadarPulse from '@/components/RadarPulse';

export default function AppPage() {
  const { hover, click } = useSound();

  return (
    <div className="max-w-5xl mx-auto px-5 py-16">
      {/* Page header */}
      <div className="text-center mb-16">
        <p className="mono text-xs tracking-[0.4em] uppercase text-[var(--color-cyan)] mb-3">
          // opspocket app
        </p>
        <h1 className="text-4xl sm:text-5xl font-bold tracking-tight">
          Your servers,{' '}
          <span className="text-[var(--color-red)]">in your pocket</span>.
        </h1>
        <p className="mt-5 text-lg text-[var(--color-muted)] max-w-xl mx-auto">
          The native iOS app for operating AI agents and the VPS they live on.
          Bring any server — SSH or MCP — and run it from anywhere.
        </p>
        <div className="mt-8 flex gap-3 justify-center">
          <Link
            href="/pricing"
            onMouseEnter={hover}
            onClick={click}
            className="btn btn-primary"
          >
            Start 7-day trial
          </Link>
          <a
            href="#features"
            onMouseEnter={hover}
            onClick={click}
            className="btn btn-ghost"
          >
            See features
          </a>
        </div>
      </div>

      {/* Feature grid */}
      <section id="features" className="grid sm:grid-cols-2 gap-6">
        <AppFeature
          icon={<Terminal />}
          title="Real terminal, real colours"
          body="Full SSH with xterm emulation, 256-colour, scrollback, paste, multi-session. Not a web shell wrapper."
        />
        <AppFeature
          icon={<Claw />}
          title="Mission Control for agents"
          body="Dispatch tasks, tail live output, inspect memory. Talks MCP natively so bridges like OpenClaw plug in instantly."
        />
        <AppFeature
          icon={<Files />}
          title="SFTP file browser"
          body="Upload a config, download a log, chmod a key — without context-switching to a computer."
        />
        <AppFeature
          icon={<Fleet />}
          title="Multi-server fleet view"
          body="Health tiles for CPU, RAM, disk, uptime on every server, updated in real time."
        />
        <AppFeature
          icon={<Slash />}
          title="Slash command palette"
          body="Type '/' and dispatch the most common ops on the currently-selected server. Fast, keyboard-first."
        />
        <AppFeature
          icon={<Lock />}
          title="Keys in your Keychain"
          body="Private keys live in iOS Keychain, not in app memory. Biometric unlock on launch."
        />
      </section>

      {/* Pitch block */}
      <section className="mt-20 border border-[var(--color-border)] rounded-2xl p-8 sm:p-12 bg-[var(--color-card)] relative overflow-hidden">
        <div className="absolute -top-10 -right-10 opacity-30">
          <RadarPulse size={24} color="var(--color-cyan)" />
        </div>
        <p className="mono text-xs tracking-[0.35em] uppercase text-[var(--color-red)] mb-3">
          // who it's for
        </p>
        <h2 className="text-3xl font-bold max-w-2xl">
          If you already have a VPS, this is the last SSH client you'll need.
        </h2>
        <p className="mt-5 text-[var(--color-muted)] max-w-2xl leading-relaxed">
          You've already picked your provider (Hetzner, DigitalOcean, Vultr,
          OVH — whatever). You've got OpenClaw or your own stack running.
          What you don't have is a mobile experience that treats your
          servers like first-class citizens. OpsPocket does.
        </p>
        <div className="mt-8">
          <Link
            href="/pricing"
            onMouseEnter={hover}
            onClick={click}
            className="btn btn-primary"
          >
            Get the app — $9/mo
            <span aria-hidden>→</span>
          </Link>
        </div>
      </section>

      {/* Upgrade cross-sell */}
      <motion.section
        initial={{ opacity: 0, y: 16 }}
        whileInView={{ opacity: 1, y: 0 }}
        viewport={{ once: true, amount: 0.3 }}
        transition={{ duration: 0.5 }}
        className="mt-16 text-center"
      >
        <div className="hairline mx-auto w-48 mb-8" />
        <p className="mono text-xs tracking-[0.35em] uppercase text-[var(--color-cyan)]">
          // don't have a VPS?
        </p>
        <h3 className="mt-3 text-2xl font-semibold">
          Let us host it for you — app is included.
        </h3>
        <p className="mt-3 text-[var(--color-muted)] max-w-md mx-auto">
          OpsPocket Cloud starts at $24/mo. Managed OpenClaw on NVMe infra,
          auto-SSL, daily backups, and the app fully unlocked.
        </p>
        <div className="mt-6">
          <Link
            href="/cloud"
            onMouseEnter={hover}
            onClick={click}
            className="btn btn-ghost"
          >
            Explore OpsPocket Cloud
          </Link>
        </div>
      </motion.section>
    </div>
  );
}

function AppFeature({
  icon,
  title,
  body,
}: {
  icon: React.ReactNode;
  title: string;
  body: string;
}) {
  return (
    <div className="tile border border-[var(--color-border)] bg-[var(--color-card)] rounded-xl p-6">
      <div className="mb-4 text-[var(--color-red)]">{icon}</div>
      <h3 className="text-lg font-semibold">{title}</h3>
      <p className="mt-2 text-sm text-[var(--color-muted)] leading-relaxed">{body}</p>
    </div>
  );
}

/* ── Inline icons (no asset deps) ─────────────────────────────────────────── */
const iconProps = {
  width: 24,
  height: 24,
  fill: 'none',
  stroke: 'currentColor',
  strokeWidth: 1.5,
  strokeLinecap: 'round' as const,
  strokeLinejoin: 'round' as const,
};
const Terminal = () => (
  <svg {...iconProps} viewBox="0 0 24 24">
    <rect x="3" y="4" width="18" height="16" rx="2" />
    <path d="m7 9 3 3-3 3M13 15h4" />
  </svg>
);
const Claw = () => (
  <svg {...iconProps} viewBox="0 0 24 24">
    <circle cx="12" cy="12" r="9" />
    <circle cx="12" cy="12" r="2" fill="currentColor" />
    <path d="M12 3v4M12 17v4M3 12h4M17 12h4" />
  </svg>
);
const Files = () => (
  <svg {...iconProps} viewBox="0 0 24 24">
    <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8Z" />
    <path d="M14 2v6h6M9 13h6M9 17h4" />
  </svg>
);
const Fleet = () => (
  <svg {...iconProps} viewBox="0 0 24 24">
    <rect x="3" y="4" width="18" height="5" rx="1" />
    <rect x="3" y="15" width="18" height="5" rx="1" />
    <circle cx="7" cy="6.5" r="0.7" fill="currentColor" />
    <circle cx="7" cy="17.5" r="0.7" fill="currentColor" />
  </svg>
);
const Slash = () => (
  <svg {...iconProps} viewBox="0 0 24 24">
    <rect x="3" y="4" width="18" height="16" rx="2" />
    <path d="m10 16 4-8M8 9h1M8 15h1" />
  </svg>
);
const Lock = () => (
  <svg {...iconProps} viewBox="0 0 24 24">
    <rect x="5" y="11" width="14" height="10" rx="2" />
    <path d="M8 11V7a4 4 0 0 1 8 0v4" />
  </svg>
);

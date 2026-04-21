'use client';

import Link from 'next/link';
import { motion } from 'framer-motion';
import { useSound } from '@/components/SoundManager';
import RadarPulse from '@/components/RadarPulse';

const steps = [
  { id: '01', title: 'Subscribe', body: 'Pick a tier, pay with any card. 14-day free trial, cancel any time.' },
  { id: '02', title: 'We provision', body: 'Dedicated NVMe VPS spun up with OpenClaw, auto-SSL, and the MCP bridge ready to accept your app.' },
  { id: '03', title: 'Connect', body: 'Open OpsPocket, paste the one-time code we email you. Done. No Docker, no SSH keys, no DevOps.' },
];

const included = [
  'Dedicated VPS, never shared',
  'NVMe SSD storage',
  'Auto-renewing TLS via Let’s Encrypt',
  'Daily backups to a second region',
  'OpenClaw pre-installed and updated',
  'Supabase + Telegram integrations ready',
  'MCP endpoint behind per-tenant Bearer auth',
  'OpsPocket app unlocked — included',
];

export default function CloudPage() {
  const { hover, click } = useSound();

  return (
    <div className="max-w-5xl mx-auto px-5 py-16">
      {/* Hero */}
      <div className="text-center mb-16 relative">
        <div className="pointer-events-none absolute inset-0 flex items-start justify-center opacity-40 mt-4">
          <RadarPulse size={14} color="var(--color-cyan)" sound />
        </div>
        <p className="mono text-xs tracking-[0.4em] uppercase text-[var(--color-cyan)] mb-3 relative">
          // opspocket cloud
        </p>
        <h1 className="text-4xl sm:text-5xl font-bold tracking-tight relative">
          Fully managed AI agents.{' '}
          <span className="text-[var(--color-red)]">Zero DevOps.</span>
        </h1>
        <p className="mt-5 text-lg text-[var(--color-muted)] max-w-xl mx-auto">
          We rent the box, install OpenClaw, keep it patched, and hand you a
          mobile app to drive it. Subscribe, chat, get things done.
        </p>
        <div className="mt-8 flex gap-3 justify-center">
          <Link
            href="/pricing"
            onMouseEnter={hover}
            onClick={click}
            className="btn btn-primary"
          >
            Start 14-day trial
          </Link>
          <a
            href="#how"
            onMouseEnter={hover}
            onClick={click}
            className="btn btn-ghost"
          >
            How it works
          </a>
        </div>
      </div>

      {/* How it works */}
      <section id="how" className="mb-20">
        <p className="mono text-xs tracking-[0.35em] uppercase text-[var(--color-red)] mb-4">
          // three steps
        </p>
        <h2 className="text-3xl font-bold mb-8">Blank box to working agent in under 5 minutes.</h2>
        <div className="grid sm:grid-cols-3 gap-5">
          {steps.map((s, i) => (
            <motion.div
              key={s.id}
              initial={{ opacity: 0, y: 16 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true, amount: 0.4 }}
              transition={{ duration: 0.45, delay: i * 0.1 }}
              className="tile border border-[var(--color-border)] bg-[var(--color-card)] rounded-xl p-6"
            >
              <p className="mono text-xs tracking-[0.3em] uppercase text-[var(--color-red)]">
                {s.id}
              </p>
              <h3 className="mt-2 text-xl font-semibold">{s.title}</h3>
              <p className="mt-2 text-sm text-[var(--color-muted)] leading-relaxed">{s.body}</p>
            </motion.div>
          ))}
        </div>
      </section>

      {/* Comparison vs competitors */}
      <section className="mb-20">
        <p className="mono text-xs tracking-[0.35em] uppercase text-[var(--color-cyan)] mb-4">
          // vs the alternatives
        </p>
        <h2 className="text-3xl font-bold mb-8">Why OpsPocket Cloud.</h2>
        <div className="overflow-x-auto border border-[var(--color-border)] rounded-xl">
          <table className="w-full mono text-sm">
            <thead>
              <tr className="bg-[var(--color-card)] border-b border-[var(--color-border)]">
                <th className="text-left p-4 text-[var(--color-muted)] font-normal uppercase text-xs tracking-[0.2em]">
                  Feature
                </th>
                <th className="p-4 text-[var(--color-red)] font-bold uppercase text-xs tracking-[0.2em]">
                  OpsPocket Cloud
                </th>
                <th className="p-4 text-[var(--color-muted)] font-normal uppercase text-xs tracking-[0.2em]">
                  xCloud
                </th>
                <th className="p-4 text-[var(--color-muted)] font-normal uppercase text-xs tracking-[0.2em]">
                  MyClaw
                </th>
                <th className="p-4 text-[var(--color-muted)] font-normal uppercase text-xs tracking-[0.2em]">
                  DIY VPS
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[var(--color-border)]">
              <Row label="Native mobile app" ops="✓" x="—" m="—" diy="—" />
              <Row label="Managed deploy + updates" ops="✓" x="✓" m="✓" diy="—" />
              <Row label="Auto-SSL" ops="✓" x="✓" m="✓" diy="setup" />
              <Row label="Daily backups" ops="✓" x="—" m="✓" diy="—" />
              <Row label="Multi-server fleet view" ops="✓" x="—" m="—" diy="—" />
              <Row label="BYO VPS supported" ops="✓ (App tier)" x="—" m="—" diy="✓" />
              <Row label="Starting price" ops="$9 / $24" x="$24" m="$17 yearly" diy="$5+" />
            </tbody>
          </table>
        </div>
      </section>

      {/* Included */}
      <section className="mb-20">
        <p className="mono text-xs tracking-[0.35em] uppercase text-[var(--color-red)] mb-4">
          // included in every plan
        </p>
        <h2 className="text-3xl font-bold mb-8">One subscription. All of this.</h2>
        <ul className="grid sm:grid-cols-2 gap-3">
          {included.map((item) => (
            <li
              key={item}
              className="flex items-start gap-3 mono text-sm text-white"
            >
              <span
                className="mt-1 inline-block w-2 h-2 rounded-full"
                style={{
                  background: 'var(--color-red)',
                  boxShadow: '0 0 8px var(--color-red)',
                }}
              />
              {item}
            </li>
          ))}
        </ul>
      </section>

      {/* Final CTA */}
      <section className="text-center border border-[var(--color-border)] rounded-2xl p-10 bg-[var(--color-card)]">
        <h2 className="text-3xl font-bold">Your agent, running in 5 minutes.</h2>
        <p className="mt-3 text-[var(--color-muted)] max-w-xl mx-auto">
          Cancel any time, export your data any time. We handle the infra; you
          handle the bots.
        </p>
        <div className="mt-6">
          <Link
            href="/pricing"
            onMouseEnter={hover}
            onClick={click}
            className="btn btn-primary"
          >
            See pricing
          </Link>
        </div>
      </section>
    </div>
  );
}

function Row({
  label,
  ops,
  x,
  m,
  diy,
}: {
  label: string;
  ops: string;
  x: string;
  m: string;
  diy: string;
}) {
  return (
    <tr>
      <td className="p-4 text-[var(--color-muted)]">{label}</td>
      <td className="p-4 text-center text-[var(--color-red)] font-bold">{ops}</td>
      <td className="p-4 text-center text-[var(--color-muted)]">{x}</td>
      <td className="p-4 text-center text-[var(--color-muted)]">{m}</td>
      <td className="p-4 text-center text-[var(--color-muted)]">{diy}</td>
    </tr>
  );
}

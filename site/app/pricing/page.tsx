'use client';

import Link from 'next/link';
import { motion } from 'framer-motion';
import { useSound } from '@/components/SoundManager';

const tiers = [
  {
    id: 'app',
    name: 'App',
    price: '$9',
    cadence: '/mo',
    kicker: 'The mobile app',
    tagline: 'Bring your own VPS. Connect via SSH or MCP.',
    cta: 'Start 7-day trial',
    features: [
      'Native iOS app',
      'Unlimited servers',
      'SSH + MCP + SFTP',
      'Multi-server health tiles',
      'Slash command palette',
      'Keys in iOS Keychain',
    ],
  },
  {
    id: 'starter',
    name: 'Cloud Starter',
    price: '$24',
    cadence: '/mo',
    kicker: 'Most popular',
    tagline: 'Managed OpenClaw + app included. 1 vCPU · 2 GB NVMe.',
    cta: 'Start 14-day trial',
    highlight: true,
    features: [
      'Everything in App',
      'Dedicated managed VPS',
      'OpenClaw pre-installed',
      'Auto-SSL + daily backups',
      'Supabase + Telegram ready',
      'Single bot, moderate traffic',
    ],
  },
  {
    id: 'pro',
    name: 'Cloud Pro',
    price: '$49',
    cadence: '/mo',
    kicker: 'Multi-bot pipelines',
    tagline: '2 vCPU · 4 GB NVMe. Built for parallel agents.',
    cta: 'Start 14-day trial',
    features: [
      'Everything in Starter',
      'Priority support',
      'More headroom for pipelines',
      'Multiple concurrent agents',
      'Task log retention extended',
    ],
  },
  {
    id: 'agency',
    name: 'Cloud Agency',
    price: '$99',
    cadence: '/mo',
    kicker: 'Agency-grade',
    tagline: '4 vCPU · 8 GB NVMe. Built for production workloads.',
    cta: 'Contact sales',
    features: [
      'Everything in Pro',
      'Uptime SLA',
      'Dedicated support channel',
      'Pipeline orchestration',
      'Heavier-spec NVMe infra',
    ],
  },
];

export default function PricingPage() {
  const { hover, click } = useSound();

  return (
    <div className="max-w-6xl mx-auto px-5 py-16">
      {/* Hero */}
      <div className="text-center mb-14">
        <p className="mono text-xs tracking-[0.4em] uppercase text-[var(--color-cyan)] mb-3">
          // pricing
        </p>
        <h1 className="text-4xl sm:text-5xl font-bold tracking-tight">
          Pick the right tier. Change any time.
        </h1>
        <p className="mt-5 text-lg text-[var(--color-muted)] max-w-xl mx-auto">
          Start with the app alone, upgrade to managed when you want us to run
          the box too. The app is always included with Cloud.
        </p>
      </div>

      {/* Tier cards */}
      <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-5">
        {tiers.map((t, i) => {
          const highlight = t.highlight;
          return (
            <motion.div
              key={t.id}
              initial={{ opacity: 0, y: 24 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true, amount: 0.2 }}
              transition={{ duration: 0.5, delay: i * 0.08 }}
              className={`tile relative flex flex-col rounded-2xl p-6 border ${
                highlight
                  ? 'border-[var(--color-red)] bg-[var(--color-card)]'
                  : 'border-[var(--color-border)] bg-[var(--color-card)]'
              }`}
              style={highlight ? { boxShadow: '0 16px 48px -12px rgba(255,59,31,0.35)' } : undefined}
            >
              {highlight && (
                <span className="absolute -top-3 left-1/2 -translate-x-1/2 mono text-[10px] tracking-[0.3em] uppercase bg-[var(--color-red)] text-black px-3 py-1 rounded-full">
                  Most popular
                </span>
              )}
              <p className="mono text-[11px] tracking-[0.3em] uppercase text-[var(--color-red)]">
                {t.kicker}
              </p>
              <h3 className="mt-2 text-xl font-semibold">{t.name}</h3>
              <div className="mt-4 flex items-baseline gap-1">
                <span className="text-4xl font-bold tracking-tight">{t.price}</span>
                <span className="mono text-xs text-[var(--color-muted)]">{t.cadence}</span>
              </div>
              <p className="mt-3 text-sm text-[var(--color-muted)] leading-relaxed">{t.tagline}</p>

              <ul className="mt-5 space-y-2 text-sm">
                {t.features.map((f) => (
                  <li key={f} className="flex items-start gap-2">
                    <span
                      aria-hidden
                      className="mt-1 inline-block w-1.5 h-1.5 rounded-full"
                      style={{ background: 'var(--color-red)' }}
                    />
                    <span className="text-white/90">{f}</span>
                  </li>
                ))}
              </ul>

              <div className="mt-6 pt-5 border-t border-[var(--color-border)]">
                <Link
                  href={
                    t.id === 'agency'
                      ? 'mailto:sales@opspocket.app?subject=Agency%20tier'
                      : `#checkout-${t.id}`
                  }
                  onMouseEnter={hover}
                  onClick={click}
                  className={`btn w-full justify-center ${
                    highlight ? 'btn-primary' : 'btn-ghost'
                  }`}
                >
                  {t.cta}
                </Link>
              </div>
            </motion.div>
          );
        })}
      </div>

      {/* FAQ */}
      <section className="mt-20">
        <p className="mono text-xs tracking-[0.35em] uppercase text-[var(--color-cyan)] mb-4">
          // questions we get
        </p>
        <h2 className="text-3xl font-bold mb-8">FAQ.</h2>
        <div className="grid sm:grid-cols-2 gap-5">
          <Faq
            q="What happens when I upgrade from App to Cloud?"
            a="We provision a managed VPS for you immediately and credit any unused App time against your first Cloud invoice. Your app stays connected — we just add the managed server to your fleet."
          />
          <Faq
            q="Can I cancel mid-billing cycle?"
            a="Yes, any time, from inside the app. No phone calls. We keep your data live for 14 days so you can re-subscribe or export. After that it's wiped."
          />
          <Faq
            q="Can I bring my own OpenAI key?"
            a="Absolutely. You paste it once; we store it encrypted and never leave it on disk in plaintext. Or use ours on the Agency tier."
          />
          <Faq
            q="Where are the Cloud servers located?"
            a="London (LHR) and Frankfurt (FRA) by default, with more regions coming. Pick at signup."
          />
          <Faq
            q="Do you support OpenClaw versions other than the default?"
            a="Starter + Pro ship the latest stable release. Agency can pin to any tagged version and we'll apply patches on request."
          />
          <Faq
            q="Is there a free tier?"
            a="No — both App and Cloud start with a free trial (7 and 14 days). We charge what running reliable managed agents costs, and skip ads entirely."
          />
        </div>
      </section>

      {/* Bottom CTA */}
      <section className="mt-20 text-center">
        <div className="hairline mx-auto w-48 mb-8" />
        <h2 className="text-3xl font-bold">Ready when you are.</h2>
        <p className="mt-3 text-[var(--color-muted)]">One card. Seven days free. Cancel any time.</p>
        <div className="mt-6 flex gap-3 justify-center">
          <Link
            href="#checkout-starter"
            onMouseEnter={hover}
            onClick={click}
            className="btn btn-primary"
          >
            Start Cloud Starter
          </Link>
          <Link
            href="#checkout-app"
            onMouseEnter={hover}
            onClick={click}
            className="btn btn-ghost"
          >
            Just the App
          </Link>
        </div>
      </section>
    </div>
  );
}

function Faq({ q, a }: { q: string; a: string }) {
  return (
    <div className="border border-[var(--color-border)] rounded-xl p-5 bg-[var(--color-card)]">
      <p className="mono text-xs tracking-[0.2em] uppercase text-[var(--color-red)]">Q</p>
      <h3 className="mt-1 font-semibold">{q}</h3>
      <p className="mt-3 text-sm text-[var(--color-muted)] leading-relaxed">{a}</p>
    </div>
  );
}

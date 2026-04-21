'use client';

/**
 * Top navigation — sits on every page. Left: logo. Centre: product links.
 * Right: mute toggle + CTA. Uses click/hover sounds from SoundManager.
 */

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useSound } from './SoundManager';

const links = [
  { href: '/app', label: 'App' },
  { href: '/cloud', label: 'Cloud' },
  { href: '/pricing', label: 'Pricing' },
];

export default function Nav() {
  const { hover, click, muted, toggleMute } = useSound();
  const pathname = usePathname();

  return (
    <nav className="fixed top-0 inset-x-0 z-50 border-b border-[var(--color-border)] bg-black/80 backdrop-blur-md">
      <div className="max-w-6xl mx-auto px-5 h-14 flex items-center justify-between">
        <Link
          href="/"
          className="flex items-center gap-2 mono font-bold tracking-[0.15em] text-sm text-white"
          onMouseEnter={hover}
          onClick={click}
        >
          <span
            aria-hidden
            className="w-2 h-2 rounded-full"
            style={{ background: 'var(--color-red)', boxShadow: '0 0 8px var(--color-red)' }}
          />
          OPSPOCKET
        </Link>

        <div className="hidden sm:flex gap-7">
          {links.map((l) => {
            const active = pathname === l.href;
            return (
              <Link
                key={l.href}
                href={l.href}
                onMouseEnter={hover}
                onClick={click}
                className={`mono text-xs uppercase tracking-[0.2em] transition ${
                  active
                    ? 'text-[var(--color-red)]'
                    : 'text-[var(--color-muted)] hover:text-white'
                }`}
              >
                {l.label}
              </Link>
            );
          })}
        </div>

        <div className="flex items-center gap-3">
          <button
            onClick={() => {
              click();
              toggleMute();
            }}
            onMouseEnter={hover}
            aria-label={muted ? 'Unmute' : 'Mute'}
            className="mono text-xs uppercase tracking-[0.15em] text-[var(--color-muted)] hover:text-white transition"
          >
            {muted ? '[ sound off ]' : '[ sound on ]'}
          </button>
          <Link
            href="/pricing"
            onMouseEnter={hover}
            onClick={click}
            className="mono text-xs uppercase tracking-[0.15em] px-3 py-1.5 rounded border border-[var(--color-red)] text-[var(--color-red)] hover:bg-[var(--color-red)] hover:text-black transition"
          >
            Get Started
          </Link>
        </div>
      </div>
    </nav>
  );
}

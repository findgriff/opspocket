import './globals.css';
import type { Metadata } from 'next';
import Nav from '@/components/Nav';
import { SoundProvider } from '@/components/SoundManager';

export const metadata: Metadata = {
  title: 'OpsPocket — Mobile command centre for AI agents',
  description:
    'OpsPocket is a mobile app + managed cloud for running and operating AI agents. SSH, MCP, and mission control — from your pocket.',
  openGraph: {
    title: 'OpsPocket',
    description: 'Mobile command centre for AI agents.',
    siteName: 'OpsPocket',
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <SoundProvider>
          <Nav />
          <main className="pt-14">{children}</main>
          <footer className="border-t border-[var(--color-border)] mt-24">
            <div className="max-w-6xl mx-auto px-5 py-10 flex flex-col sm:flex-row gap-4 sm:items-center sm:justify-between">
              <p className="mono text-xs tracking-[0.2em] uppercase text-[var(--color-muted)]">
                © OpsPocket · Mobile ops for AI agents
              </p>
              <div className="flex gap-6 mono text-xs uppercase tracking-[0.2em] text-[var(--color-muted)]">
                <a href="/app" className="hover:text-white">App</a>
                <a href="/cloud" className="hover:text-white">Cloud</a>
                <a href="/pricing" className="hover:text-white">Pricing</a>
              </div>
            </div>
          </footer>
        </SoundProvider>
      </body>
    </html>
  );
}

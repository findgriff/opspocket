# OpsPocket marketing site

Next.js 15 + Tailwind v4 + Framer Motion. Lives at `site/` inside the main
OpsPocket repo so the marketing voice can evolve alongside the product.

## Pages

| Route | Purpose |
|-------|---------|
| `/` | Hero + boot animation + product teaser + pricing link |
| `/app` | Product page for the mobile app — BYO-VPS pitch, $9/mo |
| `/cloud` | Product page for managed hosting — $24/49/99 tiers, vs competitors |
| `/pricing` | Four-column pricing cards, FAQ, sign-up CTAs |

Every page shares the same `<Nav>`, `<SoundProvider>`, and footer via the root
layout.

## Local dev

```bash
cd site
npm install
npm run dev
# open http://localhost:3000
```

## Build + deploy

```bash
npm run build       # next build → exports to out/
```

`next.config.mjs` uses `output: 'export'` so the result is a plain static
site — deployable to Vercel, Netlify, S3+CloudFront, GitHub Pages, anywhere.
When we need server-side Stripe webhooks or a provisioning orchestrator,
remove the `output` line and deploy on Vercel's standard runtime.

## The boot sequence + sound design

The homepage runs a branded intro on first load:

1. Scanline sweeps top → bottom (cyan).
2. Claw/crosshair mark materialises in the centre.
3. `boot` sound fires — low sawtooth sweep + short sine click.
4. First radar pulse emanates from the claw; subsequent pulses repeat every
   ~2.7s at the top of the hero.
5. Typewriter prints **OPSPOCKET // MISSION READY** with per-keystroke
   white-noise ticks (very quiet).
6. Hero copy + CTAs fade up. Handoff to idle state at ~2.2s.

All sounds are **synthesized via Web Audio** — no MP3 assets. That means:

- Zero asset pipeline, works offline, no CDN dependency.
- Silent until user first interacts (browser autoplay policy — handled).
- Respects `prefers-reduced-motion`: the intro + radar collapse to static
  fallbacks if the OS asks us to.
- A persistent mute toggle sits in the top nav (`[ sound on ]` / `[ sound off ]`)
  and the preference is saved to `localStorage`.

When you want to upgrade to recorded audio (a branded jingle, better radar
ping, etc), replace the body of `tone()` / `noise()` in
`components/SoundManager.tsx` with `new Audio('/sounds/foo.mp3').play()`
and keep the same public API (`sfx.boot()`, `sfx.click()`, etc).

## Brand tokens

All colours + fonts are declared in `app/globals.css` under `@theme`. They
mirror `lib/app/theme/app_theme.dart` from the Flutter app so the site and
the installed app feel like one product:

```
--color-red    #FF3B1F   primary accent
--color-cyan   #00E6FF   secondary accent / status
--color-bg     #000000
--font-mono    JetBrains Mono  (loaded from Google Fonts)
```

## What's deliberately missing (ship the rest post-launch)

- **Stripe Checkout wiring.** `href="#checkout-*"` is a placeholder; swap
  to `https://buy.stripe.com/<id>` or a serverless route once products are
  configured.
- **Contact / sales form.** Agency tier links to a `mailto:`. Good enough
  for launch, replace with a form when volume requires it.
- **Newsletter capture.** Add one line to the footer when you start a mailing
  list.
- **Live app screenshots.** Feature grid currently uses inline SVGs. Drop in
  real iPhone mockups when ready.
- **Open Graph / Twitter preview images.** Set `opengraph-image.png` at the
  repo root for automatic handling.
- **Analytics.** No tracking scripts yet — add Plausible or Fathom before
  first paid traffic.

These are deliberately not pre-built — they're all one-afternoon additions
and shouldn't be blocked on the site scaffolding.

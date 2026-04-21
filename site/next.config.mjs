/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // Static export so we can deploy to any static host (Vercel, Netlify, S3,
  // GitHub Pages). Remove the `output` line when we need server-side rendering
  // (e.g. Stripe webhooks, provisioning orchestrator).
  output: 'export',
  images: { unoptimized: true },
};
export default nextConfig;

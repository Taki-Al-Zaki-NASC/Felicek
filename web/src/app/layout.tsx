import type { Metadata, Viewport } from 'next';
import { SessionProvider } from '@/lib/session';
import './globals.css';

export const metadata: Metadata = {
  title: 'Felicek — Verified talent. Zero spam. Fair fees, always.',
  description:
    'A verified freelance marketplace with escrow milestones, live skill '
    + 'challenges and built-in calling.',
};

/**
 * Without this, mobile browsers assume a ~980px desktop layout and scale the
 * whole page down — which makes every Tailwind breakpoint useless, because the
 * reported width is never small. This was missing, which is why the site read
 * as "not responsive" regardless of the classes on it.
 *
 * maximumScale is deliberately left alone: capping zoom is an accessibility
 * regression, and the input sizing fix (16px on phones) already removes the
 * reason people usually reach for it.
 */
export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  themeColor: '#f7f5f0',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <SessionProvider>{children}</SessionProvider>
      </body>
    </html>
  );
}

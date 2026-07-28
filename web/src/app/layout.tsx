import type { Metadata } from 'next';
import { SessionProvider } from '@/lib/session';
import './globals.css';

export const metadata: Metadata = {
  title: 'Felicek — Verified talent. Zero spam. Fair fees, always.',
  description:
    'A verified freelance marketplace with escrow milestones, live skill '
    + 'challenges and built-in calling.',
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

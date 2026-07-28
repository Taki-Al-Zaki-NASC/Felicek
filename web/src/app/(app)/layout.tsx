import { Gate } from '@/components/gate';
import { Nav } from '@/components/nav';

export default function AppLayout({ children }: { children: React.ReactNode }) {
  return (
    <Gate>
      <Nav />
      <main className="mx-auto max-w-6xl px-5 py-8">{children}</main>
    </Gate>
  );
}

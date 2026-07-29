import { Gate } from '@/components/gate';
import { Nav } from '@/components/nav';

export default function AppLayout({ children }: { children: React.ReactNode }) {
  return (
    <Gate>
      <Nav />
      {/* pb-24 on phones clears the fixed bottom bar; without it the last
          row of any list sits underneath it and cannot be tapped. */}
      <main className="mx-auto max-w-6xl px-4 pb-24 pt-6 sm:px-5 sm:py-8 md:pb-8">
        {children}
      </main>
    </Gate>
  );
}

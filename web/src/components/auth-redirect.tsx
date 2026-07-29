'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useSession } from '@/lib/session';

/**
 * Sends an already-signed-in visitor out of the auth pages.
 *
 * Without this, signing in "does nothing": onAuthStateChanged fires, the
 * session updates, and the form stays on screen because nothing navigates. It
 * reads as a dead button, which is exactly what was reported.
 *
 * Driven by session stage rather than by the submit handler, so it also covers
 * arriving at /signin with a live session, and a sign-in completing in another
 * tab.
 */
export function RedirectWhenSignedIn() {
  const { stage } = useSession();
  const router = useRouter();

  useEffect(() => {
    if (stage === 'booting' || stage === 'signedOut' || stage === 'stalled') return;
    // Every other stage means authenticated. The gate decides what they can
    // actually see; this only gets them off the auth form.
    router.replace('/dashboard');
  }, [stage, router]);

  return null;
}

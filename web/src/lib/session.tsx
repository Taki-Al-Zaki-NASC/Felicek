'use client';

import { createContext, useContext, useEffect, useState } from 'react';
import { onAuthStateChanged, type User } from 'firebase/auth';
import { doc, onSnapshot } from 'firebase/firestore';
import { firebase } from './firebase';
import type { AppUser } from './types';

type Stage = 'booting' | 'signedOut' | 'onboarding' | 'verification' | 'ready' | 'stalled';

interface Session {
  stage: Stage;
  user: AppUser | null;
  error: string | null;
}

const SessionContext = createContext<Session>({
  stage: 'booting', user: null, error: null,
});

export const useSession = () => useContext(SessionContext);

/**
 * Owns "who is signed in and what should they see".
 *
 * The watchdog is not optional. On Android, a signed-in account whose profile
 * document never arrived (rules not deployed, offline) left the app on a
 * splash screen permanently — Firestore streams stay *silent* rather than
 * erroring when a read is denied. Same failure mode here, same fix.
 */
export function SessionProvider({ children }: { children: React.ReactNode }) {
  const [session, setSession] = useState<Session>({
    stage: 'booting', user: null, error: null,
  });

  useEffect(() => {
    const fb = firebase();
    if (!fb) {
      setSession({ stage: 'stalled', user: null,
        error: 'Firebase is not configured for this build.' });
      return;
    }

    let stopProfile: (() => void) | undefined;
    let watchdog: ReturnType<typeof setTimeout> | undefined;

    const stopAuth = onAuthStateChanged(fb.auth, (fbUser: User | null) => {
      stopProfile?.();
      clearTimeout(watchdog);

      if (!fbUser) {
        setSession({ stage: 'signedOut', user: null, error: null });
        return;
      }

      watchdog = setTimeout(() => {
        setSession((s) => s.user ? s : {
          stage: 'stalled', user: null,
          error: 'Signed in, but your profile did not load. The Firestore '
            + 'rules may not be deployed for this project.',
        });
      }, 12_000);

      stopProfile = onSnapshot(
        doc(fb.db, 'users', fbUser.uid),
        (snap) => {
          clearTimeout(watchdog);
          if (!snap.exists()) return; // watchdog handles a doc that never lands
          const user = { uid: snap.id, ...snap.data() } as AppUser;
          setSession({ stage: stageFor(user), user, error: null });
        },
        (e) => {
          clearTimeout(watchdog);
          setSession({ stage: 'stalled', user: null, error: e.message });
        },
      );
    });

    return () => { stopAuth(); stopProfile?.(); clearTimeout(watchdog); };
  }, []);

  return (
    <SessionContext.Provider value={session}>{children}</SessionContext.Provider>
  );
}

function stageFor(u: AppUser): Stage {
  if (!u.onboarded || !u.profileComplete) return 'onboarding';
  if (!(u.kyc.stage === 'verified' && u.kyc.depositPaid)) return 'verification';
  return 'ready';
}

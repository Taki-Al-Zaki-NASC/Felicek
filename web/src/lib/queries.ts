'use client';

import { useEffect, useState } from 'react';
import {
  collection, limit as fbLimit, onSnapshot, orderBy, query, where,
  type Query, type QueryConstraint,
} from 'firebase/firestore';
import { firebase } from './firebase';

export interface Live<T> {
  data: T[];
  loading: boolean;
  /** A sentence, never a raw exception. */
  error: string | null;
}

/**
 * Subscribes to a collection.
 *
 * Errors are surfaced, never swallowed into an empty list. An audit of the
 * Android app found the opposite everywhere — a denied read rendered as "0
 * proposals" or an empty roster, which reads as a confident wrong answer
 * rather than a failure. Callers here get `error` and must show it.
 */
export function useCollection<T>(
  path: string | null,
  constraints: QueryConstraint[] = [],
  deps: unknown[] = [],
): Live<T> {
  const [state, setState] = useState<Live<T>>({ data: [], loading: true, error: null });

  useEffect(() => {
    if (!path) { setState({ data: [], loading: false, error: null }); return; }
    const fb = firebase();
    if (!fb) {
      setState({ data: [], loading: false, error: 'Firebase is not configured for this build.' });
      return;
    }

    const q = query(collection(fb.db, path), ...constraints) as Query;
    const stop = onSnapshot(
      q,
      (snap) => setState({
        data: snap.docs.map((d) => ({ id: d.id, ...d.data() }) as T),
        loading: false,
        error: null,
      }),
      (e) => setState({
        data: [],
        loading: false,
        error: e.code === 'permission-denied'
          ? 'You do not have access to this, or the security rules have not been deployed for this project.'
          : 'That could not be loaded. Check your connection and try again.',
      }),
    );
    return stop;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [path, ...deps]);

  return state;
}

export const openJobs = (max = 25) =>
  [where('status', '==', 'open'), orderBy('createdAt', 'desc'), fbLimit(max)];

export const myJobs = (uid: string) =>
  [where('ownerId', '==', uid), orderBy('createdAt', 'desc')];

export const myProposals = (uid: string) =>
  [where('freelancerId', '==', uid), orderBy('createdAt', 'desc')];

export const proposalsForJob = (jobId: string) =>
  [where('jobId', '==', jobId), orderBy('createdAt', 'desc')];

export const myChats = (uid: string) =>
  [where('participants', 'array-contains', uid), orderBy('lastMessageAt', 'desc')];

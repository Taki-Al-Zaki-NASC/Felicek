'use client';

import { useState } from 'react';
import { useSession } from '@/lib/session';
import {
  checkReference, DOCUMENT_LABELS, PRIMARY_DOCUMENTS, type DocumentType,
} from '@/lib/identity-check';
import type { CheckResult } from '@/lib/identity-check';
import { prepareDocument } from '@/lib/image-web';
import { describeError, submitIdentity } from '@/lib/mutations';
import { DEPOSIT_CENTS } from '@/lib/types';
import { Button, Card, ErrorState, Pill, SectionLabel, money } from '@/components/ui';

/**
 * Identity verification and the deposit gate.
 *
 * Screening runs in the browser before anything uploads, and names the fix for
 * each failure — the person is still holding the document, so "rest it on a
 * flat surface" now beats a rejection three days later.
 *
 * It is screening, not proofing: it cannot tell you a document is genuine, and
 * nothing running in the claimant's own browser could. The page says so.
 */
export default function Verify() {
  const { user } = useSession();
  const [type, setType] = useState<DocumentType>('nationalId');
  const [reference, setReference] = useState('');
  const [refError, setRefError] = useState<string | null>(null);
  const [docShot, setDocShot] = useState<{ b64: string; check: CheckResult } | null>(null);
  const [selfie, setSelfie] = useState<{ b64: string; check: CheckResult } | null>(null);
  const [failed, setFailed] = useState<Record<string, CheckResult>>({});
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!user) return null;

  const done = user.kyc.idSubmitted;
  const ready = Boolean(docShot && selfie) && checkReference(type, reference) === null;

  async function capture(file: File | undefined, isFace: boolean) {
    if (!file) return;
    setBusy(true);
    try {
      const { check, base64 } = await prepareDocument(file, isFace);
      const key = isFace ? 'selfie' : 'document';
      if (!check.passed || !base64) {
        setFailed((f) => ({ ...f, [key]: check }));
        if (isFace) setSelfie(null); else setDocShot(null);
        return;
      }
      setFailed((f) => { const n = { ...f }; delete n[key]; return n; });
      if (isFace) setSelfie({ b64: base64, check });
      else setDocShot({ b64: base64, check });
    } finally {
      setBusy(false);
    }
  }

  async function submit() {
    const refIssue = checkReference(type, reference);
    if (refIssue) { setRefError(refIssue); return; }
    if (!ready || !user || !docShot || !selfie) return;
    setBusy(true); setError(null);
    try {
      await submitIdentity({
        uid: user.uid, type, reference,
        documentBase64: docShot.b64, selfieBase64: selfie.b64,
        documentCheck: docShot.check, selfieCheck: selfie.check,
      });
    } catch (e) {
      setError(describeError(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="mx-auto max-w-lg">
      <h1 className="font-serif text-2xl font-semibold sm:text-3xl">Verification</h1>
      <p className="mt-2 text-sm text-ink-muted">
        Every Felicek account needs identity on file and a cleared deposit
        before it can post or bid. There is no skip.
      </p>

      <section className="mt-8">
        <SectionLabel>Identity</SectionLabel>
        {done ? (
          <Card className="mt-3 flex items-center justify-between">
            <span className="text-sm">
              {DOCUMENT_LABELS[(user.kyc.idDocumentType as DocumentType) ?? 'nationalId']} on file
            </span>
            <Pill tone="teal">Submitted</Pill>
          </Card>
        ) : (
          <>
            <div className="mt-3 flex flex-wrap gap-2">
              {PRIMARY_DOCUMENTS.map((t) => (
                <button key={t} onClick={() => setType(t)} aria-pressed={type === t}
                  className={`rounded-[9px] px-3 py-1.5 text-xs font-semibold transition ${
                    type === t ? 'bg-teal text-white' : 'bg-backdrop text-ink-muted'
                  }`}>
                  {DOCUMENT_LABELS[t]}
                </button>
              ))}
            </div>

            <label className="mt-4 block">
              <span className="text-xs font-semibold text-ink-muted">Document number</span>
              <input value={reference}
                onChange={(e) => { setReference(e.target.value); setRefError(null); }}
                className="mt-1.5 w-full rounded-field border border-border bg-surface px-3.5 py-3 text-base outline-none focus:border-teal sm:text-sm" />
              {refError && <span className="mt-1 block text-xs text-danger">{refError}</span>}
            </label>

            <Capture label="Photo of the document"
              hint="Flat surface, all four corners in frame."
              captured={Boolean(docShot)} result={failed.document}
              onFile={(f) => void capture(f, false)} busy={busy} />

            <Capture label="Selfie" hint="Face the camera in good light."
              captured={Boolean(selfie)} result={failed.selfie}
              onFile={(f) => void capture(f, true)} busy={busy} capture="user" />

            {error && <div className="mt-4"><ErrorState message={error} /></div>}

            <Button className="mt-5 w-full" busy={busy} disabled={!ready} onClick={submit}>
              Submit for verification
            </Button>
            <p className="mt-3 text-xs text-ink-faint">
              Checks run on this device and confirm the photos are legible — they
              do not confirm the document is genuine. Submitting a document that
              is not yours costs you the account and the deposit.
            </p>
          </>
        )}
      </section>

      <section className="mt-10">
        <SectionLabel>Deposit</SectionLabel>
        <Card className="mt-3">
          <div className="flex items-center justify-between">
            <span className="font-serif text-2xl font-semibold">
              {money(DEPOSIT_CENTS[user.role])}
            </span>
            {user.kyc.depositPaid
              ? <Pill tone="teal">Cleared</Pill>
              : <Pill>{done ? 'Ready to pay' : 'Verify ID first'}</Pill>}
          </div>
          <p className="mt-3 text-sm text-ink-muted">
            {user.role === 'freelancer'
              ? 'A refundable trust bond, released after your first completed job.'
              : 'A job-posting balance — your money, spent into escrow when you hire.'}
          </p>
          <p className="mt-3 text-xs text-ink-faint">
            Payment runs through the external gateway from the Android app for
            now. The web checkout needs the server webhook that marks an intent
            paid — the client cannot mark its own payment cleared, by design.
            See docs/PAYMENTS.md.
          </p>
        </Card>
      </section>
    </div>
  );
}

function Capture({ label, hint, captured, result, onFile, busy, capture }: {
  label: string; hint: string; captured: boolean;
  result?: CheckResult; onFile: (f: File | undefined) => void;
  busy: boolean; capture?: 'user' | 'environment';
}) {
  const failed = result && !result.passed;
  return (
    <div className={`mt-3 rounded-card border p-4 ${
      captured ? 'border-teal/40 bg-teal-tint'
        : failed ? 'border-danger/40 bg-danger-tint' : 'border-border bg-surface'
    }`}>
      <div className="flex items-center justify-between gap-3">
        <div>
          <p className="text-sm font-semibold">{label}</p>
          <p className="mt-0.5 text-xs text-ink-muted">{captured ? 'Looks good' : hint}</p>
        </div>
        <label className="cursor-pointer text-xs font-bold text-teal-deep">
          {captured ? 'Replace' : 'Choose file'}
          <input type="file" accept="image/*" capture={capture} className="hidden"
            disabled={busy}
            onChange={(e) => onFile(e.target.files?.[0])} />
        </label>
      </div>
      {failed && (
        <ul className="mt-2 space-y-1">
          {result!.reasons.map((r) => (
            <li key={r} className="text-xs text-danger">• {r}</li>
          ))}
        </ul>
      )}
    </div>
  );
}

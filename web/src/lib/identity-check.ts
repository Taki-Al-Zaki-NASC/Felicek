/**
 * On-device screening for identity photos, ported from
 * app/lib/data/services/identity_check.dart.
 *
 * **Screening, not identity proofing.** It rejects input a reviewer could not
 * use — blurred, dark, blown out, a thumbnail, a number that cannot belong to
 * the chosen document type. It cannot tell you a document is genuine, and
 * nothing running in the claimant's own browser could: the machine that
 * captures the image can fabricate it.
 *
 * Thresholds are copied from the Dart implementation. If they drift, the same
 * photo passes on one surface and fails on the other.
 */

export const MIN_SHARPNESS = 22;
export const MIN_BRIGHTNESS = 45;
export const MAX_BRIGHTNESS = 232;
export const MIN_LONG_EDGE = 640;

export interface CheckResult {
  passed: boolean;
  reasons: string[];
  sharpness: number;
  brightness: number;
  width: number;
  height: number;
}

export type DocumentType =
  | 'nationalId' | 'passport' | 'drivingLicence' | 'governmentId' | 'birthCertificate';

export const DOCUMENT_LABELS: Record<DocumentType, string> = {
  nationalId: 'National ID',
  passport: 'Passport',
  drivingLicence: "Driver's licence",
  governmentId: 'Other government ID',
  birthCertificate: 'Birth certificate',
};

/** Primary documents — the birth certificate is secondary, as in the app. */
export const PRIMARY_DOCUMENTS: DocumentType[] =
  ['nationalId', 'passport', 'drivingLicence', 'governmentId'];

const MIN_LENGTH: Record<DocumentType, number> = {
  nationalId: 6, passport: 6, drivingLicence: 5, governmentId: 5, birthCertificate: 5,
};

/** Format only — it cannot confirm the number was ever issued. */
export function checkReference(type: DocumentType, raw: string): string | null {
  const value = raw.trim().toUpperCase().replace(/[\s-]/g, '');
  if (!value) return 'Enter the document number.';
  if (value.length < MIN_LENGTH[type]) {
    return `That is shorter than a ${DOCUMENT_LABELS[type].toLowerCase()} number.`;
  }
  if (value.length > 30) return 'That is longer than any document number.';
  if (!/^[A-Z0-9]+$/.test(value)) {
    return 'Use only the letters and digits printed on the document.';
  }
  if (/^(.)\1+$/.test(value)) return 'That does not look like a real document number.';
  if (type === 'passport' && !/^[A-Z0-9]{6,9}$/.test(value)) {
    return 'A passport number is 6–9 letters and digits.';
  }
  return null;
}

/** Variance of the Laplacian — the standard cheap focus measure. */
function varianceOfLaplacian(g: Uint8ClampedArray, w: number, h: number): number {
  if (w < 3 || h < 3) return 0;
  const out: number[] = [];
  for (let y = 1; y < h - 1; y++) {
    for (let x = 1; x < w - 1; x++) {
      const i = y * w + x;
      out.push(-4 * g[i] + g[i - 1] + g[i + 1] + g[i - w] + g[i + w]);
    }
  }
  if (!out.length) return 0;
  const mean = out.reduce((a, b) => a + b, 0) / out.length;
  return out.reduce((s, v) => s + (v - mean) ** 2, 0) / out.length;
}

/**
 * Screens an already-decoded image.
 *
 * Takes greyscale data rather than a File so the arithmetic is testable
 * without a browser — the canvas decode happens in the caller.
 */
export function inspectGreyscale(
  grey: Uint8ClampedArray, w: number, h: number,
  originalW: number, originalH: number,
  isFace = false,
): CheckResult {
  const sharpness = varianceOfLaplacian(grey, w, h);
  let total = 0, count = 0;
  for (let i = 0; i < grey.length; i += 4) { total += grey[i]; count++; }
  const brightness = count ? total / count : 0;

  const reasons: string[] = [];
  if (Math.max(originalW, originalH) < MIN_LONG_EDGE) {
    reasons.push('That image is too small to read — use a photo from the camera '
      + 'rather than a thumbnail.');
  }
  if (sharpness < MIN_SHARPNESS) {
    reasons.push(isFace
      ? 'That photo is blurred. Hold still and try again.'
      : 'The photo is blurred. Rest the document on a flat surface and let the '
        + 'camera focus before you shoot.');
  }
  if (brightness < MIN_BRIGHTNESS) reasons.push('Too dark to read. Move somewhere brighter.');
  else if (brightness > MAX_BRIGHTNESS) {
    reasons.push('Too bright — the glare is washing out the detail.');
  }

  return {
    passed: reasons.length === 0,
    reasons, sharpness, brightness,
    width: originalW, height: originalH,
  };
}

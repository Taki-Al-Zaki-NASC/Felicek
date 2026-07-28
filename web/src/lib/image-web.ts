/**
 * Browser-side image decode, screening and downsizing.
 *
 * Separated from identity-check.ts so the screening arithmetic stays testable
 * in Node without a DOM.
 */
import { inspectGreyscale, type CheckResult } from './identity-check';

const DOC_MAX_EDGE = 1280;
const DOC_QUALITY = 0.82;

async function toBitmap(file: File): Promise<ImageBitmap | null> {
  try {
    return await createImageBitmap(file);
  } catch {
    // A file that is not a decodable image, or a codec the browser refuses.
    return null;
  }
}

export interface Prepared {
  check: CheckResult;
  /** Base64 JPEG without the data: prefix. Null when the check failed. */
  base64: string | null;
}

/**
 * Screens a captured file and, if it passes, encodes it for storage.
 *
 * Screening runs on the original, never on the downsized copy — measuring
 * after a resize measures the resize.
 */
export async function prepareDocument(file: File, isFace = false): Promise<Prepared> {
  const bitmap = await toBitmap(file);
  if (!bitmap) {
    return {
      check: {
        passed: false,
        reasons: ['That file is not a readable image.'],
        sharpness: 0, brightness: 0, width: 0, height: 0,
      },
      base64: null,
    };
  }

  // Screen on a bounded copy so a 12 MP photo does not stall the main thread,
  // but report the original dimensions so the size check means something.
  const sw = Math.min(bitmap.width, 900);
  const sh = Math.round((sw / bitmap.width) * bitmap.height);
  const small = new OffscreenCanvas(sw, sh);
  const sctx = small.getContext('2d')!;
  sctx.drawImage(bitmap, 0, 0, sw, sh);
  const pixels = sctx.getImageData(0, 0, sw, sh).data;

  const grey = new Uint8ClampedArray(sw * sh);
  for (let i = 0, p = 0; i < pixels.length; i += 4, p++) {
    grey[p] = (pixels[i] * 0.299 + pixels[i + 1] * 0.587 + pixels[i + 2] * 0.114) | 0;
  }

  const check = inspectGreyscale(grey, sw, sh, bitmap.width, bitmap.height, isFace);
  if (!check.passed) { bitmap.close(); return { check, base64: null }; }

  const scale = Math.min(1, DOC_MAX_EDGE / Math.max(bitmap.width, bitmap.height));
  const w = Math.round(bitmap.width * scale);
  const h = Math.round(bitmap.height * scale);
  const out = new OffscreenCanvas(w, h);
  out.getContext('2d')!.drawImage(bitmap, 0, 0, w, h);
  bitmap.close();

  const blob = await out.convertToBlob({ type: 'image/jpeg', quality: DOC_QUALITY });
  const buf = new Uint8Array(await blob.arrayBuffer());
  let binary = '';
  for (const byte of buf) binary += String.fromCharCode(byte);
  return { check, base64: btoa(binary) };
}

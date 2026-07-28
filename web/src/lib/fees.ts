/**
 * Fee arithmetic, mirroring app/lib/data/models/wallet.dart.
 *
 * The gateway's charge and Felicek's 1% stay separate everywhere. Blending
 * them is how a platform that advertises 1% quietly charges four.
 */

export interface GatewaySchedule {
  key: string;
  label: string;
  /** Fraction, so 0.029 is 2.9%. */
  rate: number;
  fixedCents: number;
}

export const CARD: GatewaySchedule =
  { key: 'card', label: 'Card', rate: 0.029, fixedCents: 30 };
export const LOCAL: GatewaySchedule =
  { key: 'local', label: 'Local transfer', rate: 0.02, fixedCents: 0 };

export const PLATFORM_RATE = 0.01;

export function gatewayCharge(s: GatewaySchedule, cents: number) {
  return cents <= 0 ? 0 : Math.round(cents * s.rate) + s.fixedCents;
}

export function rateLabel(s: GatewaySchedule) {
  const pct = (s.rate * 100).toFixed(1).replace(/\.0$/, '');
  return s.fixedCents === 0 ? `${pct}%` : `${pct}% + $${(s.fixedCents / 100).toFixed(2)}`;
}

export interface Breakdown {
  grossCents: number;
  gatewayCents: number;
  platformCents: number;
  totalFeeCents: number;
  netCents: number;
  grossPlusFeesCents: number;
  feesExceedAmount: boolean;
  schedule: GatewaySchedule;
}

export function breakdown(amountCents: number, schedule = CARD): Breakdown {
  const gross = Math.max(0, amountCents);
  const gateway = gatewayCharge(schedule, gross);
  const platform = Math.round(gross * PLATFORM_RATE);
  const total = gateway + platform;
  return {
    grossCents: gross,
    gatewayCents: gateway,
    platformCents: platform,
    totalFeeCents: total,
    // On a small enough transfer the flat charge exceeds the amount; a
    // negative payout is not a thing that can happen.
    netCents: Math.max(0, gross - total),
    grossPlusFeesCents: gross + total,
    feesExceedAmount: gross > 0 && total >= gross,
    schedule,
  };
}

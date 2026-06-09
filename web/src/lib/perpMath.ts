export const ONE = 10n ** 18n;
export const BPS = 10_000n;
export const VIRTUAL = 10n ** 6n; // matches PerpVault.VIRTUAL

/** notional (ETH) = leverage * margin / ONE. `leverage` is 1e18-scaled. */
export function notionalFromMargin(leverage: bigint, margin: bigint): bigint {
  return (leverage * margin) / ONE;
}

/** index units = leverage * margin / level. */
export function unitsFromMargin(leverage: bigint, margin: bigint, level: bigint): bigint {
  if (level === 0n) return 0n;
  return (leverage * margin) / level;
}

export function openFee(notional: bigint, openFeeBps: bigint): bigint {
  return (notional * openFeeBps) / BPS;
}

/** Signed PnL (ETH). long: units*(level-entry)/ONE ; short: the negative. */
export function pnl(isLong: boolean, units: bigint, entryLevel: bigint, level: bigint): bigint {
  const diff = ((level - entryLevel) * units) / ONE;
  return isLong ? diff : -diff;
}

/**
 * Index level at which equity == maintenance margin (closed form; equity is linear in level).
 * feesOwed = borrowOwed + fundOwed (>=0 typical). Clamped to >= 0.
 */
export function liqLevel(
  isLong: boolean,
  entryLevel: bigint,
  units: bigint,
  margin: bigint,
  feesOwed: bigint,
  notional: bigint,
  mmBps: bigint
): bigint {
  if (units === 0n) return 0n;
  const maint = (notional * mmBps) / BPS;
  const delta = (ONE * (maint + feesOwed - margin)) / units; // signed
  const liq = isLong ? entryLevel + delta : entryLevel - delta;
  return liq < 0n ? 0n : liq;
}

export function utilization(reserved: bigint, assets: bigint): bigint {
  if (assets === 0n) return ONE;
  return reserved >= assets ? ONE : (reserved * ONE) / assets;
}

/** Per-second borrow rate (1e18-scaled), mirrors FundingMath.borrowDelta. */
export function borrowRatePerSec(borrowBase: bigint, reserved: bigint, assets: bigint): bigint {
  return (borrowBase * utilization(reserved, assets)) / ONE;
}

/** Per-second signed funding rate (1e18-scaled). Positive => longs pay. */
export function fundingRatePerSec(fundK: bigint, longOI: bigint, shortOI: bigint): bigint {
  const total = longOI + shortOI;
  if (total === 0n) return 0n;
  const skew = ((longOI - shortOI) * ONE) / total;
  return (fundK * skew) / ONE;
}

/** Implied ETH/USDC price for a single CALL@K leg: x = K/(1-level). Null if level >= 1. */
export function levelToPrice(strike: bigint, level: bigint): bigint | null {
  if (level >= ONE) return null;
  return (strike * ONE) / (ONE - level);
}

/** CALL@K level from price (mirror IndexBasket): x<=K ? 0 : 1 - K/x. */
export function priceToLevel(strike: bigint, x: bigint): bigint {
  if (x === 0n || x <= strike) return 0n;
  return ONE - (strike * ONE) / x;
}

/** LP share value in ETH (mirror PerpVault.withdraw share math). */
export function shareValue(shares: bigint, assets: bigint, totalShares: bigint): bigint {
  if (totalShares === 0n) return 0n;
  return (shares * (assets + VIRTUAL)) / (totalShares + VIRTUAL);
}

export function poolPctBps(shares: bigint, totalShares: bigint): bigint {
  if (totalShares === 0n) return 0n;
  return (shares * BPS) / totalShares;
}

export function slipDown(value: bigint, tolBps: bigint): bigint {
  return (value * (BPS - tolBps)) / BPS;
}

export function slipUp(value: bigint, tolBps: bigint): bigint {
  return (value * (BPS + tolBps)) / BPS;
}

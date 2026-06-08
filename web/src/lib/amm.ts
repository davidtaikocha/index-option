const ONE = 10n ** 18n;
const BPS = 10_000n;

function ceilDiv(a: bigint, b: bigint): bigint {
  return (a + b - 1n) / b;
}

function sqrt(value: bigint): bigint {
  if (value < 0n) throw new Error('sqrt of negative');
  if (value < 2n) return value;
  let x = value;
  let y = (x + 1n) / 2n;
  while (y < x) {
    x = y;
    y = (x + value / x) / 2n;
  }
  return x;
}

/** P (or N) out for buying with `eth`, given the bought reserve and the other reserve. */
export function buyAmount(reserveOut: bigint, reserveOther: bigint, eth: bigint, feeBps: number): bigint {
  const a = (eth * (BPS - BigInt(feeBps))) / BPS;
  const ending = ceilDiv(reserveOut * reserveOther, reserveOther + a);
  return reserveOut + a - ending;
}

/** ETH out for selling `inAmt` of the add side, given (addReserve, otherReserve). */
export function sellAmount(addReserve: bigint, otherReserve: bigint, inAmt: bigint, feeBps: number): bigint {
  const inEff = (inAmt * (BPS - BigInt(feeBps))) / BPS;
  const a = addReserve + inEff;
  const sum = a + otherReserve;
  const disc = sum * sum - 4n * otherReserve * inEff;
  return (sum - sqrt(disc)) / 2n;
}

export function spotPriceP(reserveP: bigint, reserveN: bigint): bigint {
  const total = reserveP + reserveN;
  if (total === 0n) return 0n;
  return (reserveN * ONE) / total;
}

/** Lower-bound an output by a slippage tolerance in bps (e.g. 50 = 0.5%). */
export function applySlippage(amount: bigint, toleranceBps: number): bigint {
  return (amount * (BPS - BigInt(toleranceBps))) / BPS;
}

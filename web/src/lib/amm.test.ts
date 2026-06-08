import { describe, it, expect } from 'vitest';
import { buyAmount, sellAmount, spotPriceP, applySlippage } from './amm';

const ONE = 10n ** 18n;

describe('amm math (mirrors OptionPool)', () => {
  it('buyAmount with no fee preserves k', () => {
    const rp = 10n * ONE;
    const rn = 10n * ONE;
    const e = ONE;
    const out = buyAmount(rp, rn, e, 0);
    // new reserves: rp + e - out, rn + e ; product >= rp*rn
    const k = rp * rn;
    const kNew = (rp + e - out) * (rn + e);
    expect(kNew >= k).toBe(true);
  });

  it('buyAmount returns less with a fee', () => {
    const rp = 10n * ONE;
    const rn = 10n * ONE;
    const noFee = buyAmount(rp, rn, ONE, 0);
    const withFee = buyAmount(rp, rn, ONE, 30);
    expect(withFee < noFee).toBe(true);
  });

  it('sellAmount stays below the other reserve', () => {
    const rp = 10n * ONE;
    const rn = 10n * ONE;
    const out = sellAmount(rp, rn, ONE, 30);
    expect(out > 0n && out < rn).toBe(true);
  });

  it('spotPriceP is Rn/(Rp+Rn)', () => {
    expect(spotPriceP(3n * ONE, ONE)).toBe(ONE / 4n);
  });

  it('applySlippage floors by tolerance bps', () => {
    expect(applySlippage(1000n, 50)).toBe(995n); // 0.5%
  });
});

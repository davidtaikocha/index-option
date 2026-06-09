import { describe, it, expect } from 'vitest';
import {
  ONE, BPS, VIRTUAL,
  notionalFromMargin, unitsFromMargin, openFee, pnl, liqLevel,
  utilization, borrowRatePerSec, fundingRatePerSec,
  levelToPrice, priceToLevel, shareValue, poolPctBps, slipUp, slipDown
} from './perpMath';

describe('perpMath', () => {
  it('open preview: notional, units, fee', () => {
    const lev = 5n * ONE, margin = ONE, level = ONE / 2n; // 5x, 1 ETH, level 0.5
    expect(notionalFromMargin(lev, margin)).toBe(5n * ONE);
    expect(unitsFromMargin(lev, margin, level)).toBe(10n * ONE);
    expect(openFee(5n * ONE, 10n)).toBe(5n * ONE / 1000n); // 10bps of 5 = 0.005
  });

  it('pnl is signed and matches units*(Δlevel)', () => {
    expect(pnl(true, 10n * ONE, ONE / 2n, (ONE * 6n) / 10n)).toBe(ONE); // long +0.1*10 = 1
    expect(pnl(false, 10n * ONE, ONE / 2n, (ONE * 6n) / 10n)).toBe(-ONE); // short
  });

  it('liqLevel: equity hits maintenance', () => {
    // long: margin 1, units 10, entry 0.5, notional 5, mm 5% -> maint 0.25, no fees
    // delta = ONE*(0.25 - 1)/10 = -0.075 ; liq = 0.5 - 0.075 = 0.425
    const liq = liqLevel(true, ONE / 2n, 10n * ONE, ONE, 0n, 5n * ONE, 500n);
    expect(liq).toBe((ONE * 425n) / 1000n);
  });

  it('liqLevel clamps to zero', () => {
    // huge margin -> liq would go negative -> clamp 0
    const liq = liqLevel(true, ONE / 2n, ONE, 100n * ONE, 0n, ONE, 500n);
    expect(liq).toBe(0n);
  });

  it('utilization caps at ONE', () => {
    expect(utilization(50n * ONE, 100n * ONE)).toBe(ONE / 2n);
    expect(utilization(200n * ONE, 100n * ONE)).toBe(ONE);
    expect(utilization(1n, 0n)).toBe(ONE); // assets 0 -> treat as full
  });

  it('borrow/funding rates mirror FundingMath', () => {
    expect(borrowRatePerSec(1000n, 50n * ONE, 100n * ONE)).toBe(500n); // base*0.5
    expect(fundingRatePerSec(1000n, 75n * ONE, 25n * ONE)).toBe(500n); // skew +0.5
    expect(fundingRatePerSec(1000n, 25n * ONE, 75n * ONE)).toBe(-500n);
    expect(fundingRatePerSec(1000n, 0n, 0n)).toBe(0n);
  });

  it('level <-> price inversion (CALL@2000)', () => {
    const K = 2000n * ONE;
    expect(priceToLevel(K, 4000n * ONE)).toBe(ONE / 2n); // 1 - 2000/4000
    expect(levelToPrice(K, ONE / 2n)).toBe(4000n * ONE); // x = K/(1-level)
    expect(levelToPrice(K, ONE)).toBeNull(); // level >= 1 -> undefined
  });

  it('shareValue uses the 1e6 virtual offset', () => {
    expect(shareValue(0n, 100n * ONE, 0n)).toBe(0n);
    // 10 shares of a 10-share / 12-ETH vault ~= 12 ETH (minus tiny offset dust)
    const v = shareValue(10n * ONE, 12n * ONE, 10n * ONE);
    expect(v <= 12n * ONE && 12n * ONE - v < 10n ** 9n).toBe(true);
    expect(VIRTUAL).toBe(10n ** 6n);
  });

  it('poolPctBps is shares/total in bps', () => {
    expect(poolPctBps(25n * ONE, 100n * ONE)).toBe(2500n);
    expect(poolPctBps(1n, 0n)).toBe(0n);
  });

  it('slip helpers floor/raise by tolerance bps', () => {
    expect(slipDown(1000n, 50n)).toBe(995n);
    expect(slipUp(1000n, 50n)).toBe(1005n);
  });
});

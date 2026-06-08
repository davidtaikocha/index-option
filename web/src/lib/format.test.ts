import { describe, it, expect } from 'vitest';
import {
  toUnixSeconds,
  isFutureUnix,
  isValidAddress,
  shortenAddress,
  formatBalance,
  isPositiveDecimal
} from './format';

describe('format helpers', () => {
  it('toUnixSeconds converts a datetime-local string to seconds', () => {
    expect(toUnixSeconds('2030-01-01T00:00:00Z')).toBe(1893456000n);
  });

  it('toUnixSeconds throws on invalid input', () => {
    expect(() => toUnixSeconds('not-a-date')).toThrow();
  });

  it('isFutureUnix compares against a fixed now', () => {
    const now = 1_000_000_000_000; // ms
    expect(isFutureUnix(1_000_000_001n, now)).toBe(true);
    expect(isFutureUnix(999_999_999n, now)).toBe(false);
  });

  it('isValidAddress accepts valid and rejects invalid', () => {
    expect(isValidAddress('0x32231734d2F09fAa3b6bE8c50D716a94f5519A88')).toBe(true);
    expect(isValidAddress('0x123')).toBe(false);
    expect(isValidAddress('')).toBe(false);
  });

  it('shortenAddress truncates the middle', () => {
    expect(shortenAddress('0x32231734d2F09fAa3b6bE8c50D716a94f5519A88')).toBe('0x3223…9A88');
  });

  it('formatBalance trims to max decimals', () => {
    expect(formatBalance(1_000_000_000_000_000_000n)).toBe('1');
    expect(formatBalance(1_234_567_890_000_000_000n, 4)).toBe('1.2345');
  });

  it('isPositiveDecimal validates numeric strings', () => {
    expect(isPositiveDecimal('3000')).toBe(true);
    expect(isPositiveDecimal('0.5')).toBe(true);
    expect(isPositiveDecimal('0')).toBe(false);
    expect(isPositiveDecimal('-1')).toBe(false);
    expect(isPositiveDecimal('abc')).toBe(false);
    expect(isPositiveDecimal('')).toBe(false);
  });
});

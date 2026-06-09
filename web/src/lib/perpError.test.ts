import { describe, it, expect } from 'vitest';
import { decodePerpError } from './perpError';

describe('decodePerpError', () => {
  it('maps a known custom error name in the message', () => {
    const msg = decodePerpError(new Error('reverted with custom error SlippageExceeded()'));
    expect(msg).toBe('Price moved past your slippage limit — try again.');
  });

  it('maps UtilizationExceeded', () => {
    expect(decodePerpError(new Error('UtilizationExceeded()'))).toBe(
      'That size exceeds the vault’s available liquidity.'
    );
  });

  it('falls back to the original message when unknown', () => {
    expect(decodePerpError(new Error('user rejected request'))).toBe('user rejected request');
  });

  it('handles non-Error inputs', () => {
    expect(decodePerpError('boom')).toBe('boom');
  });
});

import { isAddress, formatEther, type Address } from 'viem';

export function toUnixSeconds(datetimeLocal: string): bigint {
  const ms = new Date(datetimeLocal).getTime();
  if (Number.isNaN(ms)) throw new Error('Invalid date');
  return BigInt(Math.floor(ms / 1000));
}

export function isFutureUnix(unix: bigint, nowMs: number = Date.now()): boolean {
  return unix > BigInt(Math.floor(nowMs / 1000));
}

export function isValidAddress(value: string): value is Address {
  return isAddress(value);
}

export function shortenAddress(addr: string): string {
  return addr.length > 10 ? `${addr.slice(0, 6)}…${addr.slice(-4)}` : addr;
}

export function formatBalance(wei: bigint, maxDecimals = 6): string {
  const [int, frac = ''] = formatEther(wei).split('.');
  const trimmed = frac.slice(0, maxDecimals).replace(/0+$/, '');
  return trimmed ? `${int}.${trimmed}` : int;
}

export function isPositiveDecimal(value: string): boolean {
  const v = value.trim();
  if (!/^\d*\.?\d+$/.test(v)) return false;
  return Number(v) > 0;
}

import { writable } from 'svelte/store';
import type { Address } from 'viem';

export type AccountState = {
  address: Address | undefined;
  chainId: number | undefined;
  isConnected: boolean;
};

export const account = writable<AccountState>({
  address: undefined,
  chainId: undefined,
  isConnected: false
});

export type SeriesInfo = { series: Address; pToken: Address; nToken: Address };
export const activeSeries = writable<SeriesInfo | null>(null);

export type ToastState = { kind: 'info' | 'success' | 'error'; message: string } | null;
export const toast = writable<ToastState>(null);

let toastTimer: ReturnType<typeof setTimeout> | undefined;
export function showToast(kind: 'info' | 'success' | 'error', message: string, ms = 7000) {
  if (toastTimer) clearTimeout(toastTimer);
  toast.set({ kind, message });
  if (ms) toastTimer = setTimeout(() => toast.set(null), ms);
}

import { writable } from 'svelte/store';
import type { PerpMarket, PerpPosition } from './perp';

export const perpMarket = writable<PerpMarket | null>(null);
export const myPositions = writable<PerpPosition[]>([]);
export const isPerpAdmin = writable<boolean>(false);

import { readContract, writeContract, waitForTransactionReceipt, getPublicClient } from '@wagmi/core';
import { parseEther, type Address, type Hex } from 'viem';
import { config } from './wagmi';
import { INDEX_PERP, PERP_VAULT, INDEX_BASKET, PUSH_ORACLE, PERP_FEED_ID, PERP_DEPLOY_BLOCK } from './env';
import { indexPerpAbi } from './abi/indexPerp';
import { perpVaultAbi } from './abi/perpVault';
import { indexBasketAbi } from './abi/indexBasket';
import { pushOracleAbi } from './abi/pushOracle';

const ZERO = '0x0000000000000000000000000000000000000000';

export type PerpMarket = {
  level: bigint | null; // null when stale/unreadable
  spotValue: bigint;
  spotUpdatedAt: bigint;
  maxAge: bigint;
  strike: bigint | null; // set only for a single CALL leg of weight ONE
  longOI: bigint;
  shortOI: bigint;
  vaultAssets: bigint;
  vaultReserved: bigint;
  vaultFree: bigint;
  maxUtilBps: bigint;
  borrowBase: bigint;
  fundK: bigint;
  mmBps: bigint;
  openFeeBps: bigint;
  closeFeeBps: bigint;
  maxLeverage: bigint;
};

export type PerpPosition = {
  id: bigint;
  owner: Address;
  isLong: boolean;
  units: bigint;
  entryLevel: bigint;
  marginEth: bigint;
  entryBorrowCum: bigint;
  entryFundingCum: bigint;
  openedAt: bigint;
};

async function readBasketStrike(): Promise<bigint | null> {
  const legs = (await readContract(config, {
    address: INDEX_BASKET, abi: indexBasketAbi, functionName: 'legs'
  })) as readonly { kind: number; strike: bigint; weight: bigint }[];
  const ONE = 10n ** 18n;
  if (legs.length === 1 && legs[0].kind === 1 && legs[0].weight === ONE) return legs[0].strike;
  return null;
}

export async function readMarket(): Promise<PerpMarket> {
  // Direct, type-safe reads (matches lib/pool.ts style — the typed abi constants
  // validate each functionName; no `any`/`never` abi casts).
  const [
    spot, maxAge, strike, longOI, shortOI, assets, reserved, free, maxUtilBps,
    borrowBase, fundK, mmBps, openFeeBps, closeFeeBps, maxLeverage
  ] = await Promise.all([
    readContract(config, { address: PUSH_ORACLE, abi: pushOracleAbi, functionName: 'getSpotValue', args: [PERP_FEED_ID] }),
    readContract(config, { address: INDEX_BASKET, abi: indexBasketAbi, functionName: 'maxAge' }),
    readBasketStrike(),
    readContract(config, { address: INDEX_PERP, abi: indexPerpAbi, functionName: 'longOI' }),
    readContract(config, { address: INDEX_PERP, abi: indexPerpAbi, functionName: 'shortOI' }),
    readContract(config, { address: PERP_VAULT, abi: perpVaultAbi, functionName: 'totalAssets' }),
    readContract(config, { address: PERP_VAULT, abi: perpVaultAbi, functionName: 'reserved' }),
    readContract(config, { address: PERP_VAULT, abi: perpVaultAbi, functionName: 'freeAssets' }),
    readContract(config, { address: PERP_VAULT, abi: perpVaultAbi, functionName: 'maxUtilBps' }),
    readContract(config, { address: INDEX_PERP, abi: indexPerpAbi, functionName: 'borrowBase' }),
    readContract(config, { address: INDEX_PERP, abi: indexPerpAbi, functionName: 'fundK' }),
    readContract(config, { address: INDEX_PERP, abi: indexPerpAbi, functionName: 'mmBps' }),
    readContract(config, { address: INDEX_PERP, abi: indexPerpAbi, functionName: 'openFeeBps' }),
    readContract(config, { address: INDEX_PERP, abi: indexPerpAbi, functionName: 'closeFeeBps' }),
    readContract(config, { address: INDEX_PERP, abi: indexPerpAbi, functionName: 'maxLeverage' })
  ]);
  const [spotValue, spotUpdatedAt] = spot as [bigint, bigint];

  let level: bigint | null = null;
  try {
    level = (await readContract(config, { address: INDEX_BASKET, abi: indexBasketAbi, functionName: 'currentLevel' })) as bigint;
  } catch {
    level = null; // stale or zero price
  }

  return {
    level, spotValue, spotUpdatedAt,
    maxAge: maxAge as bigint, strike: strike as bigint | null,
    longOI: longOI as bigint, shortOI: shortOI as bigint,
    vaultAssets: assets as bigint, vaultReserved: reserved as bigint, vaultFree: free as bigint,
    maxUtilBps: maxUtilBps as bigint,
    borrowBase: borrowBase as bigint, fundK: fundK as bigint, mmBps: mmBps as bigint,
    openFeeBps: openFeeBps as bigint, closeFeeBps: closeFeeBps as bigint, maxLeverage: maxLeverage as bigint
  };
}

export async function readPosition(id: bigint): Promise<PerpPosition | null> {
  const p = (await readContract(config, {
    address: INDEX_PERP, abi: indexPerpAbi, functionName: 'positions', args: [id]
  })) as [Address, boolean, bigint, bigint, bigint, bigint, bigint, bigint];
  if (p[0] === ZERO) return null;
  return {
    id, owner: p[0], isLong: p[1], units: p[2], entryLevel: p[3],
    marginEth: p[4], entryBorrowCum: p[5], entryFundingCum: p[6], openedAt: p[7]
  };
}

export async function equityOf(id: bigint, level: bigint): Promise<{ equity: bigint; notional: bigint }> {
  const [equity, notional] = (await readContract(config, {
    address: INDEX_PERP, abi: indexPerpAbi, functionName: 'equityOf', args: [id, level]
  })) as [bigint, bigint];
  return { equity, notional };
}

/** Open position ids, optionally filtered to one owner, via event scan. */
export async function openPositionIds(owner?: Address): Promise<bigint[]> {
  const client = getPublicClient(config);
  if (!client) return [];
  const base = { address: INDEX_PERP, abi: indexPerpAbi, fromBlock: PERP_DEPLOY_BLOCK, toBlock: 'latest' as const };
  const opened = await client.getContractEvents({
    ...base, eventName: 'Opened', args: owner ? { owner } : undefined
  });
  const closed = await client.getContractEvents({ ...base, eventName: 'Closed' });
  const liq = await client.getContractEvents({ ...base, eventName: 'Liquidated' });
  const gone = new Set<string>();
  for (const e of [...closed, ...liq]) gone.add(((e.args as { id: bigint }).id).toString());
  const ids: bigint[] = [];
  for (const e of opened) {
    const id = (e.args as { id: bigint }).id;
    if (!gone.has(id.toString())) ids.push(id);
  }
  return ids;
}

export async function openPosition(isLong: boolean, leverage1e18: bigint, marginEth: string, limitLevel: bigint): Promise<void> {
  const hash = await writeContract(config, {
    address: INDEX_PERP, abi: indexPerpAbi, functionName: 'open',
    args: [isLong, leverage1e18, limitLevel], value: parseEther(marginEth)
  });
  await waitForTransactionReceipt(config, { hash });
}

export async function closePosition(id: bigint, limitLevel: bigint): Promise<void> {
  const hash = await writeContract(config, {
    address: INDEX_PERP, abi: indexPerpAbi, functionName: 'close', args: [id, limitLevel]
  });
  await waitForTransactionReceipt(config, { hash });
}

export async function addMargin(id: bigint, marginEth: string): Promise<void> {
  const hash = await writeContract(config, {
    address: INDEX_PERP, abi: indexPerpAbi, functionName: 'addMargin', args: [id], value: parseEther(marginEth)
  });
  await waitForTransactionReceipt(config, { hash });
}

export async function liquidate(id: bigint): Promise<void> {
  const hash = await writeContract(config, {
    address: INDEX_PERP, abi: indexPerpAbi, functionName: 'liquidate', args: [id]
  });
  await waitForTransactionReceipt(config, { hash });
}

export async function vaultDeposit(ethAmount: string): Promise<void> {
  const hash = await writeContract(config, {
    address: PERP_VAULT, abi: perpVaultAbi, functionName: 'deposit', value: parseEther(ethAmount)
  });
  await waitForTransactionReceipt(config, { hash });
}

export async function vaultWithdraw(shares: bigint): Promise<void> {
  const hash = await writeContract(config, {
    address: PERP_VAULT, abi: perpVaultAbi, functionName: 'withdraw', args: [shares]
  });
  await waitForTransactionReceipt(config, { hash });
}

export async function vaultShares(owner: Address): Promise<{ shares: bigint; totalShares: bigint }> {
  const [shares, totalShares] = await Promise.all([
    readContract(config, { address: PERP_VAULT, abi: perpVaultAbi, functionName: 'sharesOf', args: [owner] }),
    readContract(config, { address: PERP_VAULT, abi: perpVaultAbi, functionName: 'totalShares' })
  ]);
  return { shares: shares as bigint, totalShares: totalShares as bigint };
}

export async function pushPrice(price1e18: bigint): Promise<void> {
  const hash = await writeContract(config, {
    address: PUSH_ORACLE, abi: pushOracleAbi, functionName: 'pushPrice', args: [PERP_FEED_ID, price1e18]
  });
  await waitForTransactionReceipt(config, { hash });
}

export async function oracleAdmin(): Promise<{ keeper: Address; owner: Address }> {
  const [keeper, owner] = await Promise.all([
    readContract(config, { address: PUSH_ORACLE, abi: pushOracleAbi, functionName: 'keeper' }),
    readContract(config, { address: PUSH_ORACLE, abi: pushOracleAbi, functionName: 'owner' })
  ]);
  return { keeper: keeper as Address, owner: owner as Address };
}

export const FEED_ID: Hex = PERP_FEED_ID;

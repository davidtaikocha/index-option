import { writeContract, readContract, waitForTransactionReceipt } from '@wagmi/core';
import { parseEther, type Address } from 'viem';
import { config } from './wagmi';
import { POOL_FACTORY } from './env';
import { optionPoolFactoryAbi } from './abi/optionPoolFactory';
import { optionPoolAbi } from './abi/optionPool';
import { optionSeriesAbi } from './abi/optionSeries';
import { claimTokenAbi } from './abi/claimToken';

const ZERO = '0x0000000000000000000000000000000000000000';

export async function poolOf(series: Address): Promise<Address | null> {
  const addr = (await readContract(config, {
    address: POOL_FACTORY,
    abi: optionPoolFactoryAbi,
    functionName: 'poolOf',
    args: [series]
  })) as Address;
  return addr === ZERO ? null : addr;
}

export async function createPool(series: Address): Promise<Address> {
  const hash = await writeContract(config, {
    address: POOL_FACTORY,
    abi: optionPoolFactoryAbi,
    functionName: 'createPool',
    args: [series]
  });
  await waitForTransactionReceipt(config, { hash });
  const addr = await poolOf(series);
  if (!addr) throw new Error('Pool not found after creation');
  return addr;
}

export type PoolState = {
  reserveP: bigint;
  reserveN: bigint;
  priceP: bigint;
  feeBps: number;
  settled: boolean;
};

export async function readPool(pool: Address, series: Address): Promise<PoolState> {
  const [reserves, priceP, feeBps, settled] = await Promise.all([
    readContract(config, { address: pool, abi: optionPoolAbi, functionName: 'getReserves' }),
    readContract(config, { address: pool, abi: optionPoolAbi, functionName: 'spotPriceP' }),
    readContract(config, { address: pool, abi: optionPoolAbi, functionName: 'feeBps' }),
    readContract(config, { address: series, abi: optionSeriesAbi, functionName: 'settled' })
  ]);
  const [reserveP, reserveN] = reserves as [bigint, bigint];
  return {
    reserveP,
    reserveN,
    priceP: priceP as bigint,
    feeBps: Number(feeBps as bigint),
    settled: settled as boolean
  };
}

export async function sharesOf(pool: Address, owner: Address): Promise<bigint> {
  return (await readContract(config, {
    address: pool,
    abi: optionPoolAbi,
    functionName: 'sharesOf',
    args: [owner]
  })) as bigint;
}

export async function allowanceOf(token: Address, owner: Address, spender: Address): Promise<bigint> {
  return (await readContract(config, {
    address: token,
    abi: claimTokenAbi,
    functionName: 'allowance',
    args: [owner, spender]
  })) as bigint;
}

export async function approveMax(token: Address, spender: Address): Promise<void> {
  const hash = await writeContract(config, {
    address: token,
    abi: claimTokenAbi,
    functionName: 'approve',
    args: [spender, (1n << 256n) - 1n]
  });
  await waitForTransactionReceipt(config, { hash });
}

type Side = 'P' | 'N';

export async function buy(pool: Address, side: Side, ethAmount: string, minOut: bigint): Promise<void> {
  const hash = await writeContract(config, {
    address: pool,
    abi: optionPoolAbi,
    functionName: side === 'P' ? 'buyP' : 'buyN',
    args: [minOut],
    value: parseEther(ethAmount)
  });
  await waitForTransactionReceipt(config, { hash });
}

export async function sell(pool: Address, side: Side, tokenAmount: string, minEthOut: bigint): Promise<void> {
  const hash = await writeContract(config, {
    address: pool,
    abi: optionPoolAbi,
    functionName: side === 'P' ? 'sellP' : 'sellN',
    args: [parseEther(tokenAmount), minEthOut]
  });
  await waitForTransactionReceipt(config, { hash });
}

export async function fund(pool: Address, ethAmount: string, pricePHint: bigint): Promise<void> {
  const hash = await writeContract(config, {
    address: pool,
    abi: optionPoolAbi,
    functionName: 'fund',
    args: [pricePHint],
    value: parseEther(ethAmount)
  });
  await waitForTransactionReceipt(config, { hash });
}

export async function withdraw(pool: Address, shareAmount: bigint): Promise<void> {
  const hash = await writeContract(config, {
    address: pool,
    abi: optionPoolAbi,
    functionName: 'withdraw',
    args: [shareAmount]
  });
  await waitForTransactionReceipt(config, { hash });
}

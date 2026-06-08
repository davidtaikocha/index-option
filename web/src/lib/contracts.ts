import { writeContract, readContract, waitForTransactionReceipt } from '@wagmi/core';
import { parseEventLogs, parseUnits, parseEther, type Address } from 'viem';
import { config } from './wagmi';
import { OPTION_FACTORY, SERIES_ORACLE } from './env';
import { optionFactoryAbi } from './abi/optionFactory';
import { optionSeriesAbi } from './abi/optionSeries';
import { claimTokenAbi } from './abi/claimToken';

const FACTORY = OPTION_FACTORY;

export type SeriesAddresses = { series: Address; pToken: Address; nToken: Address };

export async function createSeries(
  strikeHuman: string,
  maturityUnix: bigint
): Promise<SeriesAddresses> {
  const strike = parseUnits(strikeHuman, 18);
  const hash = await writeContract(config, {
    address: FACTORY,
    abi: optionFactoryAbi,
    functionName: 'createSeries',
    args: [strike, maturityUnix, SERIES_ORACLE]
  });
  const receipt = await waitForTransactionReceipt(config, { hash });
  const logs = parseEventLogs({
    abi: optionFactoryAbi,
    eventName: 'OptionSeriesCreated',
    logs: receipt.logs
  });
  if (logs.length === 0) throw new Error('OptionSeriesCreated event not found in receipt');
  const args = logs[0].args as { series: Address; pToken: Address; nToken: Address };
  return { series: args.series, pToken: args.pToken, nToken: args.nToken };
}

export async function loadSeries(series: Address): Promise<SeriesAddresses & { settled: boolean }> {
  const [pToken, nToken, settled] = await Promise.all([
    readContract(config, { address: series, abi: optionSeriesAbi, functionName: 'pToken' }),
    readContract(config, { address: series, abi: optionSeriesAbi, functionName: 'nToken' }),
    readContract(config, { address: series, abi: optionSeriesAbi, functionName: 'settled' })
  ]);
  return {
    series,
    pToken: pToken as Address,
    nToken: nToken as Address,
    settled: settled as boolean
  };
}

export async function splitEth(series: Address, amountEth: string, receiver: Address): Promise<void> {
  const hash = await writeContract(config, {
    address: series,
    abi: optionSeriesAbi,
    functionName: 'split',
    args: [receiver],
    value: parseEther(amountEth)
  });
  await waitForTransactionReceipt(config, { hash });
}

export async function combineEth(series: Address, amount: string, receiver: Address): Promise<void> {
  const hash = await writeContract(config, {
    address: series,
    abi: optionSeriesAbi,
    functionName: 'combine',
    args: [parseEther(amount), receiver]
  });
  await waitForTransactionReceipt(config, { hash });
}

export async function tokenBalance(token: Address, owner: Address): Promise<bigint> {
  return (await readContract(config, {
    address: token,
    abi: claimTokenAbi,
    functionName: 'balanceOf',
    args: [owner]
  })) as bigint;
}

import { createConfig, http } from '@wagmi/core';
import { injected } from '@wagmi/connectors';
import { defineChain } from 'viem';
import { RPC_URL, CHAIN_ID, EXPLORER_URL } from './env';

export const taikoHoodi = defineChain({
  id: CHAIN_ID,
  name: 'Taiko Hoodi',
  nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: { default: { http: [RPC_URL] } },
  blockExplorers: { default: { name: 'Taikoscan', url: EXPLORER_URL } },
  testnet: true
});

export const config = createConfig({
  chains: [taikoHoodi],
  connectors: [injected()],
  transports: { [taikoHoodi.id]: http(RPC_URL) }
});

export const explorerUrl = EXPLORER_URL;

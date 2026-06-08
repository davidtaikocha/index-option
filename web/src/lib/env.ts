import type { Address } from 'viem';

// Public Taiko Hoodi testnet configuration. None of these are secrets; they are
// committed so the app builds and deploys with zero environment configuration.
export const OPTION_FACTORY = '0x32231734d2F09fAa3b6bE8c50D716a94f5519A88' as Address;
export const RPC_URL = 'https://rpc.hoodi.taiko.xyz';
export const CHAIN_ID = 167013;
export const EXPLORER_URL = 'https://hoodi.taikoscan.io';

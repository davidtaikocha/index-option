import type { Address } from 'viem';

// Public Taiko Hoodi testnet configuration. None of these are secrets; they are
// committed so the app builds and deploys with zero environment configuration.
export const OPTION_FACTORY = '0x32231734d2F09fAa3b6bE8c50D716a94f5519A88' as Address;
export const RPC_URL = 'https://rpc.hoodi.taiko.xyz';
export const CHAIN_ID = 167013;
export const EXPLORER_URL = 'https://hoodi.taikoscan.io';

// Every series is created against this fixed oracle EOA. Settlement is out of
// scope for this UI, so the oracle is not user-selectable.
export const SERIES_ORACLE = '0x5f2b097ffF3BC8fE3EB254aCCBe7E81Fe50160AA' as Address;

// OptionPoolFactory proxy (secondary-market AMM).
export const POOL_FACTORY = '0xDed394E8bb1e7E77F0B443fBdD50089aFB07d583' as Address;

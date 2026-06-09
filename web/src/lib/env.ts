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

// --- Index Perp (Product A) stack on Taiko Hoodi ---
export const INDEX_PERP = '0xB9801a41F7e05B4c00617f9F83CCcFE088Ff3215' as Address;
export const PERP_VAULT = '0x820ebA1906b01a678797092a4051112d1C044149' as Address;
export const INDEX_BASKET = '0x8D374141a424A0af9b467c7ceCD167F5b8c25Cb1' as Address;
export const PUSH_ORACLE = '0x6C1c94571A112C6754740C43C8C88FDBE947FB1c' as Address;
export const INSURANCE_FUND = '0x334d166C0246D8C73f974BFAb1a97d160115FEA2' as Address;

// bytes32("ETHUSDC") — the feed id the basket reads and the keeper pushes.
export const PERP_FEED_ID =
  '0x4554485553444300000000000000000000000000000000000000000000000000' as `0x${string}`;

// Block the perp stack was deployed at — lower bound for event scans.
export const PERP_DEPLOY_BLOCK = 11183796n;

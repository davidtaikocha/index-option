const MESSAGES: Record<string, string> = {
  SlippageExceeded: 'Price moved past your slippage limit — try again.',
  UtilizationExceeded: 'That size exceeds the vault’s available liquidity.',
  InsufficientFreeAssets: 'The vault has less withdrawable liquidity than requested.',
  NotLiquidatable: 'That position is not liquidatable right now.',
  Unauthorized: 'Only the oracle keeper/owner can do that.',
  LeverageTooHigh: 'Leverage exceeds the maximum allowed.',
  ZeroMargin: 'Enter a margin amount greater than zero.',
  StalePrice: 'The index price is stale — push a fresh price first.',
  ZeroPrice: 'The oracle has no price yet — push one first.',
  NotOwner: 'Only the position owner can do that.',
  PositionClosed: 'That position is already closed.'
};

/** Map a viem/contract revert to a friendly message; otherwise return the original text. */
export function decodePerpError(e: unknown): string {
  const text = e instanceof Error ? e.message : String(e);
  for (const name of Object.keys(MESSAGES)) {
    if (text.includes(name)) return MESSAGES[name];
  }
  return text;
}

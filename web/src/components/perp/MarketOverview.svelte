<script lang="ts">
  import { formatEther } from 'viem';
  import type { PerpMarket } from '$lib/perp';
  import { formatBalance } from '$lib/format';
  import { levelToPrice, borrowRatePerSec, fundingRatePerSec, BPS } from '$lib/perpMath';

  export let market: PerpMarket | null;
  export let onRefresh: () => void = () => {};

  // seconds since the oracle was last pushed
  $: ageSec = market ? Math.max(0, Math.floor(Date.now() / 1000) - Number(market.spotUpdatedAt)) : 0;
  $: stale = !market || market.level === null || (market.maxAge > 0n && BigInt(ageSec) > market.maxAge);

  $: impliedPrice =
    market && market.level !== null && market.strike !== null
      ? levelToPrice(market.strike, market.level)
      : null;

  $: borrowPctHr = market
    ? (Number(borrowRatePerSec(market.borrowBase, market.vaultReserved, market.vaultAssets)) / 1e18) * 3600 * 100
    : 0;
  $: fundingPctHr = market
    ? (Number(fundingRatePerSec(market.fundK, market.longOI, market.shortOI)) / 1e18) * 3600 * 100
    : 0;
  $: utilPct = market && market.vaultAssets > 0n
    ? Number((market.vaultReserved * BPS) / market.vaultAssets) / 100
    : 0;
</script>

<section class="glass-card" data-glow-border>
  <div class="p-6 lg:p-7">
    <div class="mb-5 flex items-center justify-between">
      <div class="flex items-center gap-3">
        <span class="pill flex h-7 w-7 items-center justify-center text-xs font-bold text-pink-200">≡</span>
        <h2 class="display text-lg text-grey-10">Market</h2>
      </div>
      {#if stale}
        <span class="rounded-full border border-[#EBB222]/40 bg-[#EBB222]/10 px-2.5 py-1 text-[11px] text-[#FFDC85]">stale · push a price</span>
      {:else}
        <span class="rounded-full border border-[#2fbf71]/40 bg-[#2fbf71]/10 px-2.5 py-1 text-[11px] text-[#9fe9bf]">live · {ageSec}s ago</span>
      {/if}
    </div>

    {#if !market}
      <p class="text-sm text-grey-400">Loading market…</p>
    {:else}
      <div class="space-y-2 text-sm">
        <div class="flex justify-between"><span class="text-grey-300">Index level</span>
          <span class="font-mono text-grey-100">{market.level !== null ? formatEther(market.level) : '—'} ETH</span></div>
        {#if impliedPrice !== null}
          <div class="flex justify-between"><span class="text-grey-300">Implied ETH/USDC</span>
            <span class="font-mono text-grey-100">${formatBalance(impliedPrice, 2)}</span></div>
        {/if}
        <div class="flex justify-between"><span class="text-grey-300">Funding · borrow /hr</span>
          <span class="font-mono text-grey-100">{fundingPctHr.toFixed(4)}% · {borrowPctHr.toFixed(4)}%</span></div>
        <div class="flex justify-between"><span class="text-grey-300">Long · short OI</span>
          <span class="font-mono text-grey-100">{formatBalance(market.longOI)} · {formatBalance(market.shortOI)} ETH</span></div>
        <div class="flex justify-between"><span class="text-grey-300">Vault TVL · util</span>
          <span class="font-mono text-grey-100">{formatBalance(market.vaultAssets)} ETH · {utilPct.toFixed(1)}%</span></div>
      </div>
      <button class="btn-soft mt-4 w-full py-2 text-xs" on:click={onRefresh}>Refresh</button>
    {/if}
  </div>
</section>

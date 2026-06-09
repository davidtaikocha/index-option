<script lang="ts">
  import { parseEther, formatEther } from 'viem';
  import { account, showToast } from '$lib/stores';
  import { taikoHoodi } from '$lib/wagmi';
  import type { PerpMarket } from '$lib/perp';
  import { openPosition } from '$lib/perp';
  import { decodePerpError } from '$lib/perpError';
  import { isPositiveDecimal, formatBalance } from '$lib/format';
  import {
    ONE, BPS, notionalFromMargin, unitsFromMargin, openFee, liqLevel, levelToPrice, slipUp, slipDown
  } from '$lib/perpMath';

  export let market: PerpMarket | null;
  export let onDone: () => void = () => {};

  let isLong = true;
  let marginStr = '';
  let leverageX = 5; // 1..20
  let tolBps = 50;
  let submitting = false;

  $: level = market?.level ?? null;
  $: margin = isPositiveDecimal(marginStr) ? parseEther(marginStr) : 0n;
  $: leverage = BigInt(Math.round(leverageX * 1000)) * (ONE / 1000n); // 1e18-scaled, 0.001 steps
  $: notional = level && margin > 0n ? notionalFromMargin(leverage, margin) : 0n;
  $: units = level && margin > 0n ? unitsFromMargin(leverage, margin, level) : 0n;
  $: fee = openFee(notional, market?.openFeeBps ?? 0n);
  $: marginNet = margin > fee ? margin - fee : 0n;
  $: liq = level && units > 0n && market
    ? liqLevel(isLong, level, units, marginNet, 0n, notional, market.mmBps)
    : 0n;
  $: liqPrice = market?.strike != null && liq > 0n ? levelToPrice(market.strike, liq) : null;
  $: fits = !!market && notional <= (market.vaultFree * market.maxUtilBps) / BPS;
  $: onNetwork = $account.isConnected && $account.chainId === taikoHoodi.id;
  $: canOpen = onNetwork && level !== null && margin > 0n && notional > 0n && fits && !submitting;

  async function onOpen() {
    if (!level) return;
    submitting = true;
    try {
      const limit = isLong ? slipUp(level, BigInt(tolBps)) : slipDown(level, BigInt(tolBps));
      await openPosition(isLong, leverage, marginStr, limit);
      showToast('success', `Opened ${isLong ? 'long' : 'short'}`);
      marginStr = '';
      onDone();
    } catch (e) {
      showToast('error', decodePerpError(e));
    } finally {
      submitting = false;
    }
  }
</script>

<section class="glass-card" data-glow-border>
  <div class="p-6 lg:p-7">
    <h2 class="display mb-5 text-lg text-grey-10">Open position</h2>

    <div class="mb-4 flex gap-2">
      <button class="btn-soft flex-1 py-2 text-sm {isLong ? '!border-[#2fbf71] !text-grey-10' : ''}" on:click={() => (isLong = true)}>Long</button>
      <button class="btn-soft flex-1 py-2 text-sm {!isLong ? '!border-pink-400 !text-grey-10' : ''}" on:click={() => (isLong = false)}>Short</button>
    </div>

    <div class="mb-4">
      <span class="mb-1.5 block text-xs font-medium uppercase tracking-wider text-grey-300">Margin (ETH)</span>
      <input class="input-box px-3.5 py-2.5 text-sm" type="text" inputmode="decimal" bind:value={marginStr} placeholder="1.0" />
    </div>

    <div class="mb-4">
      <div class="mb-1.5 flex justify-between text-xs text-grey-300"><span>Leverage</span><span class="font-mono text-grey-100">{leverageX.toFixed(1)}×</span></div>
      <input type="range" min="1" max="20" step="0.5" bind:value={leverageX} class="w-full accent-pink-400" />
    </div>

    <div class="rounded-[10px] border border-grey-700 bg-grey-900/30 px-3.5 py-2.5 text-xs text-grey-300 space-y-1">
      <div class="flex justify-between"><span>Entry level</span><span class="font-mono text-grey-100">{level !== null ? formatEther(level) : '—'}</span></div>
      <div class="flex justify-between"><span>Liq level{#if liqPrice} · price{/if}</span>
        <span class="font-mono text-grey-100">{liq > 0n ? formatBalance(liq, 4) : '—'}{#if liqPrice} · ${formatBalance(liqPrice, 0)}{/if}</span></div>
      <div class="flex justify-between"><span>Notional · fee</span><span class="font-mono text-grey-100">{formatBalance(notional)} · {formatBalance(fee)}</span></div>
    </div>

    <button class="btn-brand mt-4 w-full py-2.5 text-sm" on:click={onOpen} disabled={!canOpen}>
      {submitting ? 'Opening…' : `Open ${isLong ? 'long' : 'short'}`}
    </button>
    {#if market && level === null}
      <p class="mt-2 text-center text-xs text-grey-400">Index price is stale — push a price to trade.</p>
    {:else if margin > 0n && !fits}
      <p class="mt-2 text-center text-xs text-grey-400">Size exceeds the vault's available liquidity.</p>
    {:else if !onNetwork}
      <p class="mt-2 text-center text-xs text-grey-400">Connect to Taiko Hoodi to trade.</p>
    {/if}
  </div>
</section>

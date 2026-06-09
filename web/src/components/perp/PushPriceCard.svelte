<script lang="ts">
  import { parseEther, formatEther } from 'viem';
  import { showToast } from '$lib/stores';
  import type { PerpMarket } from '$lib/perp';
  import { pushPrice } from '$lib/perp';
  import { decodePerpError } from '$lib/perpError';
  import { isPositiveDecimal } from '$lib/format';

  export let market: PerpMarket | null;
  export let onDone: () => void = () => {};

  let priceStr = '';
  let busy = false;

  $: lastPrice = market && market.spotValue > 0n ? formatEther(market.spotValue) : '—';
  $: lastAge = market && market.spotUpdatedAt > 0n
    ? Math.max(0, Math.floor(Date.now() / 1000) - Number(market.spotUpdatedAt))
    : null;

  async function onPush() {
    if (!isPositiveDecimal(priceStr)) return;
    busy = true;
    try {
      await pushPrice(parseEther(priceStr));
      showToast('success', 'Price pushed');
      priceStr = '';
      onDone();
    } catch (e) {
      showToast('error', decodePerpError(e));
    } finally {
      busy = false;
    }
  }
</script>

<section class="glass-card" data-glow-border>
  <div class="p-6 lg:p-7">
    <div class="mb-4 flex items-center gap-2">
      <span class="pill px-2 py-0.5 text-[10px] text-pink-200">admin</span>
      <h2 class="display text-lg text-grey-10">Push price</h2>
    </div>
    <p class="mb-3 text-xs text-grey-400">Last: <span class="font-mono text-grey-100">{lastPrice}</span> USDC/ETH{#if lastAge !== null} · {lastAge}s ago{/if}</p>
    <div class="flex gap-2">
      <input class="input-box flex-1 px-3.5 py-2.5 text-sm" type="text" inputmode="decimal" bind:value={priceStr} placeholder="ETH/USDC e.g. 4000" />
      <button class="btn-brand shrink-0 px-4 text-sm" on:click={onPush} disabled={busy || !isPositiveDecimal(priceStr)}>{busy ? '…' : 'Push'}</button>
    </div>
  </div>
</section>

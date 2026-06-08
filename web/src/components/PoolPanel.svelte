<script lang="ts">
  import type { Address } from 'viem';
  import { account, showToast, type SeriesInfo } from '$lib/stores';
  import { taikoHoodi } from '$lib/wagmi';
  import { poolOf, createPool, readPool, type PoolState } from '$lib/pool';
  import TradeForm from '$components/TradeForm.svelte';
  import LiquidityForm from '$components/LiquidityForm.svelte';

  export let info: SeriesInfo;

  let pool: Address | null = null;
  let state: PoolState | null = null;
  let tab: 'trade' | 'liquidity' = 'trade';
  let loading = false;
  let creating = false;

  $: onCorrectNetwork = $account.isConnected && $account.chainId === taikoHoodi.id;

  async function load() {
    loading = true;
    try {
      pool = await poolOf(info.series);
      if (pool) state = await readPool(pool, info.series);
    } catch (e) {
      showToast('error', (e as Error).message);
    } finally {
      loading = false;
    }
  }

  async function onCreate() {
    creating = true;
    try {
      pool = await createPool(info.series);
      state = await readPool(pool, info.series);
      showToast('success', 'Pool created');
    } catch (e) {
      showToast('error', (e as Error).message);
    } finally {
      creating = false;
    }
  }

  // Reload whenever the active series changes.
  let lastSeries: Address | null = null;
  $: if (info.series !== lastSeries) {
    lastSeries = info.series;
    pool = null;
    state = null;
    load();
  }

  async function refresh() {
    if (pool) state = await readPool(pool, info.series);
  }
</script>

<section class="glass-card" data-glow-border>
  <div class="p-6 lg:p-7">
    <div class="mb-5 flex items-center gap-3">
      <span class="pill flex h-7 w-7 items-center justify-center text-xs font-bold text-pink-200">⇄</span>
      <h2 class="display text-lg text-grey-10">Secondary market</h2>
    </div>

    {#if loading}
      <p class="text-sm text-grey-400">Loading pool…</p>
    {:else if !pool}
      <p class="mb-4 text-sm text-grey-300">No pool exists for this series yet.</p>
      <button class="btn-brand w-full py-2.5 text-sm" on:click={onCreate} disabled={!onCorrectNetwork || creating}>
        {creating ? 'Creating…' : 'Create pool'}
      </button>
      {#if !onCorrectNetwork}
        <p class="mt-2 text-center text-xs text-grey-400">Connect to Taiko Hoodi to create a pool.</p>
      {/if}
    {:else if state}
      <div class="mb-4 flex gap-2">
        <button class="btn-soft flex-1 py-2 text-sm {tab === 'trade' ? '!border-pink-400 !text-grey-10' : ''}" on:click={() => (tab = 'trade')}>Trade</button>
        <button class="btn-soft flex-1 py-2 text-sm {tab === 'liquidity' ? '!border-pink-400 !text-grey-10' : ''}" on:click={() => (tab = 'liquidity')}>Liquidity</button>
      </div>
      {#if tab === 'trade'}
        <TradeForm {pool} pToken={info.pToken} nToken={info.nToken} {state} feeBps={state.feeBps} onDone={refresh} />
      {:else}
        <LiquidityForm {pool} {state} onDone={refresh} />
      {/if}
    {/if}
  </div>
</section>

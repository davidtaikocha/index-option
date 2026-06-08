<script lang="ts">
  import type { Address } from 'viem';
  import { account, activeSeries, showToast } from '$lib/stores';
  import { taikoHoodi } from '$lib/wagmi';
  import { loadSeries } from '$lib/contracts';
  import { isValidAddress } from '$lib/format';
  import { poolOf, createPool, readPool, type PoolState } from '$lib/pool';
  import TradeForm from '$components/TradeForm.svelte';
  import LiquidityForm from '$components/LiquidityForm.svelte';

  let manualSeries = '';
  let loadingSeries = false;
  let pool: Address | null = null;
  let state: PoolState | null = null;
  let tab: 'trade' | 'liquidity' = 'trade';
  let loading = false;
  let creating = false;

  $: onCorrectNetwork = $account.isConnected && $account.chainId === taikoHoodi.id;
  $: series = $activeSeries?.series ?? null;

  async function onLoadSeries() {
    if (!isValidAddress(manualSeries)) return;
    loadingSeries = true;
    try {
      const info = await loadSeries(manualSeries as Address);
      activeSeries.set({ series: info.series, pToken: info.pToken, nToken: info.nToken });
      showToast('success', 'Series loaded');
    } catch (e) {
      showToast('error', (e as Error).message);
    } finally {
      loadingSeries = false;
    }
  }

  async function load(s: Address) {
    loading = true;
    try {
      pool = await poolOf(s);
      if (pool) state = await readPool(pool, s);
    } catch (e) {
      showToast('error', (e as Error).message);
    } finally {
      loading = false;
    }
  }

  async function onCreate() {
    if (!series) return;
    creating = true;
    try {
      pool = await createPool(series);
      state = await readPool(pool, series);
      showToast('success', 'Pool created');
    } catch (e) {
      showToast('error', (e as Error).message);
    } finally {
      creating = false;
    }
  }

  // Reload whenever the active series changes (or clears).
  let lastSeries: Address | null = null;
  $: if (series !== lastSeries) {
    lastSeries = series;
    pool = null;
    state = null;
    if (series) load(series);
  }

  async function refresh() {
    if (pool && series) state = await readPool(pool, series);
  }
</script>

<section class="glass-card" data-glow-border>
  <div class="p-6 lg:p-7">
    <div class="mb-5 flex items-center gap-3">
      <span class="pill flex h-7 w-7 items-center justify-center text-xs font-bold text-pink-200">⇄</span>
      <h2 class="display text-lg text-grey-10">Secondary market</h2>
    </div>

    {#if !$activeSeries}
      <p class="mb-4 text-sm text-grey-300">Create a series above, or load one by address to trade its P / N pair.</p>
      <div class="flex gap-2">
        <input
          class="input-box min-w-0 flex-1 px-3.5 py-2.5 font-mono text-sm"
          type="text"
          bind:value={manualSeries}
          placeholder="0x… series address" />
        <button
          class="btn-soft shrink-0 px-4 text-sm"
          on:click={onLoadSeries}
          disabled={!isValidAddress(manualSeries) || loadingSeries}>
          {loadingSeries ? 'Loading…' : 'Load'}
        </button>
      </div>
    {:else if loading}
      <p class="text-sm text-grey-400">Loading pool…</p>
    {:else if !pool}
      <p class="mb-4 text-sm text-grey-300">No pool exists for this series yet.</p>
      <button class="btn-brand w-full py-2.5 text-sm" on:click={onCreate} disabled={!onCorrectNetwork || creating}>
        {creating ? 'Creating…' : 'Create pool'}
      </button>
      {#if !onCorrectNetwork}
        <p class="mt-2 text-center text-xs text-grey-400">Connect to Taiko Hoodi to create a pool.</p>
      {/if}
    {:else if state && $activeSeries}
      <div class="mb-4 flex gap-2">
        <button class="btn-soft flex-1 py-2 text-sm {tab === 'trade' ? '!border-pink-400 !text-grey-10' : ''}" on:click={() => (tab = 'trade')}>Trade</button>
        <button class="btn-soft flex-1 py-2 text-sm {tab === 'liquidity' ? '!border-pink-400 !text-grey-10' : ''}" on:click={() => (tab = 'liquidity')}>Liquidity</button>
      </div>
      {#if tab === 'trade'}
        <TradeForm {pool} pToken={$activeSeries.pToken} nToken={$activeSeries.nToken} {state} feeBps={state.feeBps} onDone={refresh} />
      {:else}
        <LiquidityForm {pool} {state} onDone={refresh} />
      {/if}
    {/if}
  </div>
</section>

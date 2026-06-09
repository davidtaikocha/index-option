<script lang="ts">
  import { showToast } from '$lib/stores';
  import type { PerpMarket } from '$lib/perp';
  import { openPositionIds, readPosition, equityOf, liquidate } from '$lib/perp';
  import { decodePerpError } from '$lib/perpError';
  import { shortenAddress, formatBalance } from '$lib/format';
  import { BPS } from '$lib/perpMath';

  export let market: PerpMarket | null;
  export let onDone: () => void = () => {};

  type Row = { id: bigint; owner: string; isLong: boolean; equity: bigint; maint: bigint };
  let rows: Row[] = [];
  let open = false;
  let loading = false;
  let busyId: bigint | null = null;

  async function scan() {
    if (!market || market.level === null) return;
    loading = true;
    try {
      const ids = await openPositionIds();
      const out: Row[] = [];
      for (const id of ids) {
        const pos = await readPosition(id);
        if (!pos) continue;
        const { equity, notional } = await equityOf(id, market.level);
        const maint = (notional * market.mmBps) / BPS;
        if (equity < maint) out.push({ id, owner: pos.owner, isLong: pos.isLong, equity, maint });
      }
      rows = out;
    } catch {
      // keep prior rows
    } finally {
      loading = false;
    }
  }
  $: if (open && market?.level != null) scan();

  async function onLiquidate(id: bigint) {
    busyId = id;
    try {
      await liquidate(id);
      showToast('success', `Liquidated #${id}`);
      await scan();
      onDone();
    } catch (e) {
      showToast('error', decodePerpError(e));
    } finally {
      busyId = null;
    }
  }
</script>

<section class="glass-card" data-glow-border>
  <div class="p-6 lg:p-7">
    <button class="flex w-full items-center justify-between" on:click={() => (open = !open)}>
      <h2 class="display text-lg text-grey-10">Liquidations</h2>
      <span class="text-grey-400">{open ? '▴' : '▾'}</span>
    </button>

    {#if open}
      {#if loading}
        <p class="mt-4 text-sm text-grey-400">Scanning positions…</p>
      {:else if rows.length === 0}
        <p class="mt-4 text-sm text-grey-400">No positions at risk.</p>
      {:else}
        <div class="mt-4 space-y-2">
          {#each rows as row (row.id)}
            <div class="flex items-center justify-between rounded-[10px] border border-grey-700 bg-grey-900/30 px-3 py-2 text-xs">
              <span class="font-mono text-grey-200">#{row.id} · {shortenAddress(row.owner)} · {row.isLong ? 'L' : 'S'}</span>
              <span class="font-mono text-pink-200">eq {formatBalance(row.equity, 4)} / mm {formatBalance(row.maint, 4)}</span>
              <button class="btn-soft shrink-0 px-3 py-1 text-xs" on:click={() => onLiquidate(row.id)} disabled={busyId === row.id}>{busyId === row.id ? '…' : 'Liquidate'}</button>
            </div>
          {/each}
        </div>
      {/if}
    {/if}
  </div>
</section>

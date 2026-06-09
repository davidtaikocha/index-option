<script lang="ts">
  import { parseEther, formatEther } from 'viem';
  import { showToast } from '$lib/stores';
  import type { PerpMarket, PerpPosition } from '$lib/perp';
  import { closePosition, addMargin, equityOf } from '$lib/perp';
  import { decodePerpError } from '$lib/perpError';
  import { formatBalance, isPositiveDecimal } from '$lib/format';
  import { ONE, pnl, liqLevel, levelToPrice, slipUp, slipDown } from '$lib/perpMath';

  export let position: PerpPosition;
  export let market: PerpMarket | null;
  export let onDone: () => void = () => {};

  let addStr = '';
  let tolBps = 50;
  let busy = false;
  let equity: bigint | null = null;
  let notional = 0n;

  $: level = market?.level ?? null;
  $: notionalCalc = (position.units * position.entryLevel) / ONE;
  $: pnlEth = level !== null ? pnl(position.isLong, position.units, position.entryLevel, level) : 0n;
  $: feesOwed = equity !== null && level !== null
    ? position.marginEth + pnlEth - equity // borrow+funding owed implied by equity
    : 0n;
  $: liq = level !== null && market
    ? liqLevel(position.isLong, position.entryLevel, position.units, position.marginEth, feesOwed, notionalCalc, market.mmBps)
    : 0n;
  $: liqPrice = market?.strike != null && liq > 0n ? levelToPrice(market.strike, liq) : null;
  $: leverageX = position.marginEth > 0n ? Number((notionalCalc * 100n) / position.marginEth) / 100 : 0;

  async function refreshEquity() {
    if (level === null) return;
    try {
      const r = await equityOf(position.id, level);
      equity = r.equity;
      notional = r.notional;
    } catch {
      equity = null;
    }
  }
  $: if (level !== null) refreshEquity();

  async function onClose() {
    if (level === null) return;
    busy = true;
    try {
      const limit = position.isLong ? slipDown(level, BigInt(tolBps)) : slipUp(level, BigInt(tolBps));
      await closePosition(position.id, limit);
      showToast('success', 'Position closed');
      onDone();
    } catch (e) {
      showToast('error', decodePerpError(e));
    } finally {
      busy = false;
    }
  }

  async function onAdd() {
    if (!isPositiveDecimal(addStr)) return;
    busy = true;
    try {
      await addMargin(position.id, addStr);
      showToast('success', 'Margin added');
      addStr = '';
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
    <div class="mb-4 flex items-center justify-between">
      <h2 class="display text-lg text-grey-10">Position #{position.id}</h2>
      <span class="rounded-full border px-2.5 py-1 text-[11px] {position.isLong ? 'border-[#2fbf71]/40 bg-[#2fbf71]/10 text-[#9fe9bf]' : 'border-pink-400/40 bg-pink-400/10 text-pink-200'}">
        {position.isLong ? 'Long' : 'Short'} · {leverageX.toFixed(1)}×
      </span>
    </div>

    <div class="space-y-2 text-sm">
      <div class="flex justify-between"><span class="text-grey-300">PnL</span>
        <span class="font-mono {pnlEth >= 0n ? 'text-[#9fe9bf]' : 'text-pink-200'}">{pnlEth >= 0n ? '+' : ''}{formatEther(pnlEth)} ETH</span></div>
      <div class="flex justify-between"><span class="text-grey-300">Entry · mark</span>
        <span class="font-mono text-grey-100">{formatBalance(position.entryLevel, 4)} · {level !== null ? formatBalance(level, 4) : '—'}</span></div>
      <div class="flex justify-between"><span class="text-grey-300">Liq level{#if liqPrice} · price{/if}</span>
        <span class="font-mono text-grey-100">{liq > 0n ? formatBalance(liq, 4) : '—'}{#if liqPrice} · ${formatBalance(liqPrice, 0)}{/if}</span></div>
      <div class="flex justify-between"><span class="text-grey-300">Margin · fees owed</span>
        <span class="font-mono text-grey-100">{formatBalance(position.marginEth)} · {formatBalance(feesOwed > 0n ? feesOwed : 0n)}</span></div>
    </div>

    <div class="mt-4 flex gap-2">
      <input class="input-box flex-1 px-3 py-2 text-sm" type="text" inputmode="decimal" bind:value={addStr} placeholder="+ margin ETH" />
      <button class="btn-soft shrink-0 px-3 text-sm" on:click={onAdd} disabled={busy || !isPositiveDecimal(addStr)}>Add</button>
      <button class="btn-brand shrink-0 px-4 text-sm" on:click={onClose} disabled={busy || level === null}>{busy ? '…' : 'Close'}</button>
    </div>
  </div>
</section>

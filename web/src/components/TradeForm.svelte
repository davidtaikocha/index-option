<script lang="ts">
  import type { Address } from 'viem';
  import { parseEther, formatEther } from 'viem';
  import { account, showToast } from '$lib/stores';
  import { buy, sell, allowanceOf, approveMax, type PoolState } from '$lib/pool';
  import { buyAmount, sellAmount, applySlippage } from '$lib/amm';
  import { isPositiveDecimal, formatBalance } from '$lib/format';

  export let pool: Address;
  export let pToken: Address;
  export let nToken: Address;
  export let state: PoolState;
  export let feeBps = 30;
  export let onDone: () => void = () => {};

  let side: 'P' | 'N' = 'P';
  let dir: 'buy' | 'sell' = 'buy';
  let amount = '';
  let toleranceBps = 50;
  let submitting = false;

  $: rOut = side === 'P' ? state.reserveP : state.reserveN;
  $: rOther = side === 'P' ? state.reserveN : state.reserveP;
  $: amt = isPositiveDecimal(amount) ? parseEther(amount) : 0n;
  $: quote =
    amt === 0n
      ? 0n
      : dir === 'buy'
        ? buyAmount(rOut, rOther, amt, feeBps)
        : sellAmount(rOut, rOther, amt, feeBps);
  $: minOut = applySlippage(quote, toleranceBps);
  $: canSubmit = amt > 0n && quote > 0n && $account.isConnected && !submitting && !state.settled;

  async function onSubmit() {
    submitting = true;
    try {
      if (dir === 'buy') {
        await buy(pool, side, amount, minOut);
        showToast('success', `Bought ${side}`);
      } else {
        const token = side === 'P' ? pToken : nToken;
        const current = await allowanceOf(token, $account.address as Address, pool);
        if (current < amt) await approveMax(token, pool);
        await sell(pool, side, amount, minOut);
        showToast('success', `Sold ${side}`);
      }
      amount = '';
      onDone();
    } catch (e) {
      showToast('error', (e as Error).message);
    } finally {
      submitting = false;
    }
  }
</script>

<div class="space-y-4">
  <div class="flex gap-2">
    <button class="btn-soft flex-1 py-2 text-sm {side === 'P' ? '!border-pink-400 !text-grey-10' : ''}" on:click={() => (side = 'P')}>P</button>
    <button class="btn-soft flex-1 py-2 text-sm {side === 'N' ? '!border-pink-400 !text-grey-10' : ''}" on:click={() => (side = 'N')}>N</button>
    <button class="btn-soft flex-1 py-2 text-sm {dir === 'buy' ? '!border-pink-400 !text-grey-10' : ''}" on:click={() => (dir = 'buy')}>Buy</button>
    <button class="btn-soft flex-1 py-2 text-sm {dir === 'sell' ? '!border-pink-400 !text-grey-10' : ''}" on:click={() => (dir = 'sell')}>Sell</button>
  </div>

  <div>
    <span class="mb-1.5 block text-xs font-medium uppercase tracking-wider text-grey-300">
      {dir === 'buy' ? 'ETH in' : `${side} in`}
    </span>
    <input class="input-box px-3.5 py-2.5 text-sm" type="text" inputmode="decimal" bind:value={amount} placeholder="0.1" />
  </div>

  <div class="rounded-[10px] border border-grey-700 bg-grey-900/30 px-3.5 py-2.5 text-xs text-grey-300 space-y-1">
    <div class="flex justify-between"><span>Est. {dir === 'buy' ? `${side} out` : 'ETH out'}</span><span class="font-mono text-grey-100">{formatBalance(quote)}</span></div>
    <div class="flex justify-between"><span>Min received ({(toleranceBps / 100).toFixed(2)}%)</span><span class="font-mono text-grey-100">{formatBalance(minOut)}</span></div>
    <div class="flex justify-between"><span>Spot price(P)</span><span class="font-mono text-grey-100">{formatEther(state.priceP)}</span></div>
  </div>

  <button class="btn-brand w-full py-2.5 text-sm" on:click={onSubmit} disabled={!canSubmit}>
    {submitting ? 'Submitting…' : `${dir === 'buy' ? 'Buy' : 'Sell'} ${side}`}
  </button>
  {#if state.settled}
    <p class="text-center text-xs text-grey-400">Series settled — trading is frozen.</p>
  {/if}
</div>

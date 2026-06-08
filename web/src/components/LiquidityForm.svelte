<script lang="ts">
  import type { Address } from 'viem';
  import { parseEther } from 'viem';
  import { account, showToast } from '$lib/stores';
  import { fund, withdraw, sharesOf, type PoolState } from '$lib/pool';
  import { isPositiveDecimal, formatBalance } from '$lib/format';

  export let pool: Address;
  export let state: PoolState;
  export let onDone: () => void = () => {};

  let tab: 'fund' | 'withdraw' = 'fund';
  let ethAmount = '';
  let priceP = '0.5';
  let shareAmount = '';
  let myShares: bigint | null = null;
  let submitting = false;

  $: isFirstFunder = state.reserveP === 0n && state.reserveN === 0n;
  $: canFund = isPositiveDecimal(ethAmount) && $account.isConnected && !submitting && !state.settled;
  $: canWithdraw = isPositiveDecimal(shareAmount) && $account.isConnected && !submitting;

  async function refreshShares() {
    if (!$account.address) return;
    try {
      myShares = await sharesOf(pool, $account.address as Address);
    } catch {
      // ignore transient read failures; keep prior value
    }
  }
  $: if ($account.address) refreshShares();

  async function onFund() {
    submitting = true;
    try {
      const hint = isFirstFunder && isPositiveDecimal(priceP) ? parseEther(priceP) : 0n;
      await fund(pool, ethAmount, hint);
      showToast('success', 'Liquidity added');
      ethAmount = '';
      await refreshShares();
      onDone();
    } catch (e) {
      showToast('error', (e as Error).message);
    } finally {
      submitting = false;
    }
  }

  async function onWithdraw() {
    submitting = true;
    try {
      await withdraw(pool, parseEther(shareAmount));
      showToast('success', 'Withdrew P + N — combine or redeem them on the series');
      shareAmount = '';
      await refreshShares();
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
    <button class="btn-soft flex-1 py-2 text-sm {tab === 'fund' ? '!border-pink-400 !text-grey-10' : ''}" on:click={() => (tab = 'fund')}>Fund</button>
    <button class="btn-soft flex-1 py-2 text-sm {tab === 'withdraw' ? '!border-pink-400 !text-grey-10' : ''}" on:click={() => (tab = 'withdraw')}>Withdraw</button>
  </div>

  {#if myShares !== null}
    <p class="text-xs text-grey-300">Your LP shares: <span class="font-mono text-grey-100">{formatBalance(myShares)}</span></p>
  {/if}

  {#if tab === 'fund'}
    <div>
      <span class="mb-1.5 block text-xs font-medium uppercase tracking-wider text-grey-300">ETH amount</span>
      <input class="input-box px-3.5 py-2.5 text-sm" type="text" inputmode="decimal" bind:value={ethAmount} placeholder="1.0" />
    </div>
    {#if isFirstFunder}
      <div>
        <span class="mb-1.5 block text-xs font-medium uppercase tracking-wider text-grey-300">Start price(P) · 0–1</span>
        <input class="input-box px-3.5 py-2.5 text-sm" type="text" inputmode="decimal" bind:value={priceP} placeholder="0.5" />
        <span class="mt-1.5 block text-xs text-grey-400">You're the first LP — this sets the opening price; the heavier side's excess is returned.</span>
      </div>
    {/if}
    <button class="btn-brand w-full py-2.5 text-sm" on:click={onFund} disabled={!canFund}>
      {submitting ? 'Funding…' : 'Add liquidity'}
    </button>
    {#if state.settled}
      <p class="text-center text-xs text-grey-400">Series settled — funding is frozen.</p>
    {/if}
  {:else}
    <div>
      <span class="mb-1.5 block text-xs font-medium uppercase tracking-wider text-grey-300">Shares to withdraw</span>
      <input class="input-box px-3.5 py-2.5 text-sm" type="text" inputmode="decimal" bind:value={shareAmount} placeholder="1.0" />
      <span class="mt-1.5 block text-xs text-grey-400">Returns raw P and N. Combine (or redeem after settlement) on the series to get ETH.</span>
    </div>
    <button class="btn-brand w-full py-2.5 text-sm" on:click={onWithdraw} disabled={!canWithdraw}>
      {submitting ? 'Withdrawing…' : 'Withdraw'}
    </button>
  {/if}
</div>

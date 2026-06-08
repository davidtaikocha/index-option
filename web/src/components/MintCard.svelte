<script lang="ts">
  import type { Address } from 'viem';
  import { account, activeSeries, showToast } from '$lib/stores';
  import { taikoHoodi } from '$lib/wagmi';
  import { splitEth, loadSeries, tokenBalance } from '$lib/contracts';
  import { isPositiveDecimal, isValidAddress, formatBalance } from '$lib/format';

  let manualSeries = '';
  let amount = '';
  let submitting = false;
  let pBalance: bigint | null = null;
  let nBalance: bigint | null = null;

  $: onCorrectNetwork = $account.isConnected && $account.chainId === taikoHoodi.id;
  $: target = $activeSeries?.series ?? (isValidAddress(manualSeries) ? (manualSeries as Address) : null);
  $: canSubmit = target !== null && isPositiveDecimal(amount) && onCorrectNetwork && !submitting;

  async function refreshBalances() {
    if (!$activeSeries || !$account.address) return;
    try {
      [pBalance, nBalance] = await Promise.all([
        tokenBalance($activeSeries.pToken, $account.address),
        tokenBalance($activeSeries.nToken, $account.address)
      ]);
    } catch (e) {
      pBalance = null;
      nBalance = null;
      showToast('error', (e as Error).message);
    }
  }

  async function onLoad() {
    if (!isValidAddress(manualSeries)) return;
    try {
      const info = await loadSeries(manualSeries as Address);
      activeSeries.set({ series: info.series, pToken: info.pToken, nToken: info.nToken });
      await refreshBalances();
      showToast('success', 'Series loaded');
    } catch (e) {
      showToast('error', (e as Error).message);
    }
  }

  async function onSplit() {
    if (!target || !$account.address) return;
    submitting = true;
    try {
      await splitEth(target, amount, $account.address);
      showToast('success', 'Minted P + N');
      await refreshBalances();
    } catch (e) {
      showToast('error', (e as Error).message);
    } finally {
      submitting = false;
    }
  }

  $: if ($activeSeries && $account.address) refreshBalances();
</script>

<section class="card bg-base-200 shadow-xl">
  <div class="card-body gap-4">
    <h2 class="card-title font-display">2 · Mint (split ETH → P + N)</h2>

    {#if !$activeSeries}
      <label class="form-control">
        <span class="label-text">Series address</span>
        <div class="join">
          <input class="input input-bordered join-item w-full font-mono text-sm" type="text" bind:value={manualSeries} placeholder="0x… (or create one above)" />
          <button class="btn join-item" on:click={onLoad} disabled={!isValidAddress(manualSeries)}>Load</button>
        </div>
      </label>
    {/if}

    <label class="form-control">
      <span class="label-text">ETH amount</span>
      <input class="input input-bordered" type="text" inputmode="decimal" bind:value={amount} placeholder="0.1" />
    </label>

    <button class="btn btn-primary" on:click={onSplit} disabled={!canSubmit}>
      {submitting ? 'Minting…' : 'Mint P + N'}
    </button>

    {#if pBalance !== null && nBalance !== null}
      <div class="flex gap-4 text-sm">
        <span class="badge badge-success badge-outline">P: {formatBalance(pBalance)}</span>
        <span class="badge badge-info badge-outline">N: {formatBalance(nBalance)}</span>
      </div>
    {/if}
  </div>
</section>

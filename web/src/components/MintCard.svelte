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

<section class="glass-card" data-glow-border>
  <div class="p-6 lg:p-7">
    <div class="mb-5 flex items-center gap-3">
      <span class="pill flex h-7 w-7 items-center justify-center text-xs font-bold text-pink-200">2</span>
      <h2 class="display text-lg text-grey-10">Mint · split ETH into P + N</h2>
    </div>

    <div class="space-y-4">
      {#if !$activeSeries}
        <div>
          <span class="mb-1.5 block text-xs font-medium uppercase tracking-wider text-grey-300">Series address</span>
          <div class="flex gap-2">
            <input
              class="input-box min-w-0 flex-1 px-3.5 py-2.5 font-mono text-sm"
              type="text"
              bind:value={manualSeries}
              placeholder="0x… or create one above" />
            <button class="btn-soft shrink-0 px-4 text-sm" on:click={onLoad} disabled={!isValidAddress(manualSeries)}>
              Load
            </button>
          </div>
        </div>
      {/if}

      <div>
        <span class="mb-1.5 block text-xs font-medium uppercase tracking-wider text-grey-300">ETH amount</span>
        <input
          class="input-box px-3.5 py-2.5 text-sm"
          type="text"
          inputmode="decimal"
          bind:value={amount}
          placeholder="0.1" />
      </div>

      <button class="btn-brand w-full py-2.5 text-sm" on:click={onSplit} disabled={!canSubmit}>
        {submitting ? 'Minting…' : 'Mint P + N'}
      </button>

      {#if pBalance !== null && nBalance !== null}
        <div class="flex gap-2 text-xs">
          <span class="pill flex-1 px-3 py-2 text-center font-semibold text-green-300">P · {formatBalance(pBalance)}</span>
          <span class="pill flex-1 px-3 py-2 text-center font-semibold text-pink-200">N · {formatBalance(nBalance)}</span>
        </div>
      {/if}
    </div>
  </div>
</section>

<script lang="ts">
  import { account, activeSeries, showToast } from '$lib/stores';
  import { taikoHoodi } from '$lib/wagmi';
  import { combineEth } from '$lib/contracts';
  import { isPositiveDecimal } from '$lib/format';

  let amount = '';
  let submitting = false;

  $: onCorrectNetwork = $account.isConnected && $account.chainId === taikoHoodi.id;
  $: canSubmit = $activeSeries !== null && isPositiveDecimal(amount) && onCorrectNetwork && !submitting;

  async function onCombine() {
    if (!$activeSeries || !$account.address) return;
    submitting = true;
    try {
      await combineEth($activeSeries.series, amount, $account.address);
      showToast('success', 'Combined P + N → ETH');
    } catch (e) {
      showToast('error', (e as Error).message);
    } finally {
      submitting = false;
    }
  }
</script>

<section class="glass-card" data-glow-border>
  <div class="p-6 lg:p-7">
    <div class="mb-5 flex items-center gap-3">
      <span class="pill flex h-7 w-7 items-center justify-center text-xs font-bold text-pink-200">3</span>
      <h2 class="display text-lg text-grey-10">Combine · P + N back to ETH</h2>
    </div>

    {#if !$activeSeries}
      <p class="text-sm text-grey-400">Create or load a series first.</p>
    {:else}
      <div class="space-y-4">
        <div>
          <span class="mb-1.5 block text-xs font-medium uppercase tracking-wider text-grey-300">Amount to combine</span>
          <input
            class="input-box px-3.5 py-2.5 text-sm"
            type="text"
            inputmode="decimal"
            bind:value={amount}
            placeholder="0.1" />
        </div>
        <button class="btn-brand w-full py-2.5 text-sm" on:click={onCombine} disabled={!canSubmit}>
          {submitting ? 'Combining…' : 'Combine'}
        </button>
      </div>
    {/if}
  </div>
</section>

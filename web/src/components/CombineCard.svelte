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

<section class="card bg-base-200 shadow-xl">
  <div class="card-body gap-4">
    <h2 class="card-title font-display">3 · Combine (P + N → ETH)</h2>

    {#if !$activeSeries}
      <p class="text-sm text-base-content/60">Create or load a series first.</p>
    {:else}
      <label class="form-control">
        <span class="label-text">Amount to combine</span>
        <input class="input input-bordered" type="text" inputmode="decimal" bind:value={amount} placeholder="0.1" />
      </label>
      <button class="btn btn-primary" on:click={onCombine} disabled={!canSubmit}>
        {submitting ? 'Combining…' : 'Combine'}
      </button>
    {/if}
  </div>
</section>

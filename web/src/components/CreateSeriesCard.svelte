<script lang="ts">
  import { account, activeSeries, showToast } from '$lib/stores';
  import { taikoHoodi, explorerUrl } from '$lib/wagmi';
  import { createSeries } from '$lib/contracts';
  import { SERIES_ORACLE } from '$lib/env';
  import { isPositiveDecimal, toUnixSeconds, isFutureUnix, shortenAddress } from '$lib/format';

  let strike = '';
  let maturity = '';
  let submitting = false;

  $: onCorrectNetwork = $account.isConnected && $account.chainId === taikoHoodi.id;
  $: maturityValid =
    maturity !== '' &&
    (() => {
      try {
        return isFutureUnix(toUnixSeconds(maturity));
      } catch {
        return false;
      }
    })();
  $: formValid = isPositiveDecimal(strike) && maturityValid && onCorrectNetwork;

  async function onSubmit() {
    submitting = true;
    try {
      const info = await createSeries(strike, toUnixSeconds(maturity));
      activeSeries.set(info);
      showToast('success', 'Series created');
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
      <span class="pill flex h-7 w-7 items-center justify-center text-xs font-bold text-pink-200">1</span>
      <h2 class="display text-lg text-grey-10">Create series</h2>
    </div>

    <div class="space-y-4">
      <div>
        <span class="mb-1.5 block text-xs font-medium uppercase tracking-wider text-grey-300">Strike · USDC per ETH</span>
        <input
          class="input-box px-3.5 py-2.5 text-sm"
          type="text"
          inputmode="decimal"
          bind:value={strike}
          placeholder="3000" />
      </div>

      <div>
        <span class="mb-1.5 block text-xs font-medium uppercase tracking-wider text-grey-300">Maturity</span>
        <input
          class="input-box px-3.5 py-2.5 text-sm"
          class:is-error={maturity !== '' && !maturityValid}
          type="datetime-local"
          bind:value={maturity} />
        {#if maturity !== '' && !maturityValid}
          <span class="mt-1.5 block text-xs text-red-300">Must be in the future</span>
        {/if}
      </div>

      <div class="flex items-center justify-between gap-2 rounded-[10px] border border-grey-700 bg-grey-900/30 px-3.5 py-2.5">
        <span class="text-xs uppercase tracking-wider text-grey-400">Oracle</span>
        <a
          class="font-mono text-xs text-grey-200 transition-colors hover:text-pink-200"
          href={`${explorerUrl}/address/${SERIES_ORACLE}`}
          target="_blank"
          rel="noreferrer">{shortenAddress(SERIES_ORACLE)} ↗</a>
      </div>

      <button class="btn-brand mt-1 w-full py-2.5 text-sm" on:click={onSubmit} disabled={!formValid || submitting}>
        {submitting ? 'Creating…' : 'Create series'}
      </button>
      {#if !onCorrectNetwork}
        <p class="text-center text-xs text-grey-400">Connect to Taiko Hoodi to create a series.</p>
      {/if}
    </div>
  </div>
</section>

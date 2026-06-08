<script lang="ts">
  import type { Address } from 'viem';
  import { account, activeSeries, showToast } from '$lib/stores';
  import { taikoHoodi } from '$lib/wagmi';
  import { createSeries, deployMockOracle } from '$lib/contracts';
  import { isPositiveDecimal, isValidAddress, toUnixSeconds, isFutureUnix } from '$lib/format';

  let strike = '';
  let maturity = '';
  let oracle = '';
  let deployingOracle = false;
  let submitting = false;

  $: onCorrectNetwork = $account.isConnected && $account.chainId === taikoHoodi.id;
  $: maturityValid = maturity !== '' && (() => {
    try {
      return isFutureUnix(toUnixSeconds(maturity));
    } catch {
      return false;
    }
  })();
  $: formValid =
    isPositiveDecimal(strike) && maturityValid && isValidAddress(oracle) && onCorrectNetwork;

  async function onDeployOracle() {
    deployingOracle = true;
    try {
      const addr = await deployMockOracle();
      oracle = addr;
      showToast('success', 'Mock oracle deployed');
    } catch (e) {
      showToast('error', (e as Error).message);
    } finally {
      deployingOracle = false;
    }
  }

  async function onSubmit() {
    submitting = true;
    try {
      const info = await createSeries(strike, toUnixSeconds(maturity), oracle as Address);
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

      <div>
        <span class="mb-1.5 block text-xs font-medium uppercase tracking-wider text-grey-300">Oracle address</span>
        <div class="flex gap-2">
          <input
            class="input-box min-w-0 flex-1 px-3.5 py-2.5 font-mono text-sm"
            class:is-error={oracle !== '' && !isValidAddress(oracle)}
            type="text"
            bind:value={oracle}
            placeholder="0x…" />
          <button
            class="btn-soft shrink-0 px-3.5 text-sm"
            on:click={onDeployOracle}
            disabled={!onCorrectNetwork || deployingOracle}>
            {deployingOracle ? 'Deploying…' : 'Deploy mock'}
          </button>
        </div>
        {#if oracle !== '' && !isValidAddress(oracle)}
          <span class="mt-1.5 block text-xs text-red-300">Invalid address</span>
        {/if}
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

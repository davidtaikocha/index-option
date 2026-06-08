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

<section class="card bg-base-200 shadow-xl">
  <div class="card-body gap-4">
    <h2 class="card-title font-display">1 · Create series</h2>

    <label class="form-control">
      <span class="label-text">Strike (USDC per ETH)</span>
      <input class="input input-bordered" type="text" inputmode="decimal" bind:value={strike} placeholder="3000" />
    </label>

    <label class="form-control">
      <span class="label-text">Maturity</span>
      <input class="input input-bordered" type="datetime-local" bind:value={maturity} />
      {#if maturity !== '' && !maturityValid}
        <span class="label-text-alt text-error">Must be in the future</span>
      {/if}
    </label>

    <label class="form-control">
      <span class="label-text">Oracle address</span>
      <div class="join">
        <input class="input input-bordered join-item w-full font-mono text-sm" type="text" bind:value={oracle} placeholder="0x…" />
        <button class="btn join-item" on:click={onDeployOracle} disabled={!onCorrectNetwork || deployingOracle}>
          {deployingOracle ? 'Deploying…' : 'Deploy mock'}
        </button>
      </div>
      {#if oracle !== '' && !isValidAddress(oracle)}
        <span class="label-text-alt text-error">Invalid address</span>
      {/if}
    </label>

    <button class="btn btn-primary" on:click={onSubmit} disabled={!formValid || submitting}>
      {submitting ? 'Creating…' : 'Create series'}
    </button>
    {#if !onCorrectNetwork}
      <span class="text-sm text-base-content/60">Connect to Taiko Hoodi to create a series.</span>
    {/if}
  </div>
</section>

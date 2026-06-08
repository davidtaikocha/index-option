<script lang="ts">
  import { switchChain } from '@wagmi/core';
  import { config, taikoHoodi } from '$lib/wagmi';
  import { account, showToast } from '$lib/stores';

  $: wrongNetwork = $account.isConnected && $account.chainId !== taikoHoodi.id;

  async function onSwitch() {
    try {
      await switchChain(config, { chainId: taikoHoodi.id });
    } catch (e) {
      showToast('error', (e as Error).message);
    }
  }
</script>

{#if wrongNetwork}
  <div class="alert alert-warning flex items-center justify-between">
    <span>Wrong network — switch to Taiko Hoodi.</span>
    <button class="btn btn-sm" on:click={onSwitch}>Switch</button>
  </div>
{/if}

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
  <div
    class="mb-6 flex items-center justify-between gap-3 rounded-[14px] border border-[#EBB222]/40 bg-[#EBB222]/10 px-4 py-3 text-sm backdrop-blur-sm">
    <span class="flex items-center gap-2.5 text-[#FFDC85]">
      <span class="status-dot bg-[#EBB222] shadow-[0_0_8px_#EBB222]"></span>
      Wrong network — switch to Taiko Hoodi.
    </span>
    <button class="btn-soft shrink-0 px-3.5 py-1.5 text-xs" on:click={onSwitch}>Switch</button>
  </div>
{/if}

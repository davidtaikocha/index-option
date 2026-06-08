<script lang="ts">
  import { connect, disconnect } from '@wagmi/core';
  import { injected } from '@wagmi/connectors';
  import { config } from '$lib/wagmi';
  import { account, showToast } from '$lib/stores';
  import { shortenAddress } from '$lib/format';

  async function onConnect() {
    try {
      await connect(config, { connector: injected() });
    } catch (e) {
      showToast('error', (e as Error).message);
    }
  }

  async function onDisconnect() {
    try {
      await disconnect(config);
    } catch (e) {
      showToast('error', (e as Error).message);
    }
  }
</script>

{#if $account.isConnected && $account.address}
  <button
    class="pill flex items-center gap-2.5 px-3.5 py-2 text-sm font-semibold text-grey-100 transition-colors hover:text-grey-10"
    title="Disconnect"
    on:click={onDisconnect}>
    <span class="status-dot bg-green-300 shadow-[0_0_8px_#47E0A0]"></span>
    <span class="font-mono">{shortenAddress($account.address)}</span>
  </button>
{:else}
  <button class="btn-brand px-4 py-2 text-sm" on:click={onConnect}>Connect Wallet</button>
{/if}

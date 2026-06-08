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
    await disconnect(config);
  }
</script>

{#if $account.isConnected && $account.address}
  <button class="btn btn-secondary btn-sm" on:click={onDisconnect}>
    {shortenAddress($account.address)}
  </button>
{:else}
  <button class="btn btn-primary btn-sm" on:click={onConnect}>Connect Wallet</button>
{/if}

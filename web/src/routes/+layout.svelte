<script lang="ts">
  import { onMount } from 'svelte';
  import { watchAccount, getAccount, reconnect, type GetAccountReturnType } from '@wagmi/core';
  import { config } from '$lib/wagmi';
  import { account } from '$lib/stores';
  import Toast from '$components/Toast.svelte';
  import '../app.css';

  function sync(a: GetAccountReturnType) {
    account.set({ address: a.address, chainId: a.chainId, isConnected: a.isConnected });
  }

  onMount(() => {
    reconnect(config);
    sync(getAccount(config));
    return watchAccount(config, { onChange: sync });
  });
</script>

<slot />
<Toast />

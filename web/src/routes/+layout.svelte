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

  // Feed the pointer position to CSS so [data-glow-border] cards can light up
  // along the cursor (same technique as bridge-ui).
  function syncPointer({ clientX, clientY }: PointerEvent) {
    const root = document.documentElement;
    root.style.setProperty('--x', clientX.toFixed(1));
    root.style.setProperty('--y', clientY.toFixed(1));
    root.style.setProperty('--xp', (clientX / window.innerWidth).toFixed(3));
    root.style.setProperty('--yp', (clientY / window.innerHeight).toFixed(3));
  }

  onMount(() => {
    reconnect(config);
    sync(getAccount(config));
    const unwatch = watchAccount(config, { onChange: sync });
    window.addEventListener('pointermove', syncPointer);
    return () => {
      unwatch();
      window.removeEventListener('pointermove', syncPointer);
    };
  });
</script>

<slot />
<Toast />

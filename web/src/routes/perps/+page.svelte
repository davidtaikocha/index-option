<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { account } from '$lib/stores';
  import { perpMarket, isPerpAdmin } from '$lib/perpStores';
  import { readMarket, oracleAdmin } from '$lib/perp';
  import NetworkGuard from '$components/NetworkGuard.svelte';
  import MarketOverview from '$components/perp/MarketOverview.svelte';

  let timer: ReturnType<typeof setInterval> | undefined;

  async function refresh() {
    try {
      perpMarket.set(await readMarket());
    } catch {
      // keep prior market on transient read failure
    }
  }

  async function refreshAdmin() {
    if (!$account.address) {
      isPerpAdmin.set(false);
      return;
    }
    try {
      const { keeper, owner } = await oracleAdmin();
      const me = ($account.address as string).toLowerCase();
      isPerpAdmin.set(me === keeper.toLowerCase() || me === owner.toLowerCase());
    } catch {
      isPerpAdmin.set(false);
    }
  }

  $: if ($account.address !== undefined) refreshAdmin();

  onMount(() => {
    refresh();
    timer = setInterval(refresh, 12_000);
  });
  onDestroy(() => timer && clearInterval(timer));
</script>

<main class="mx-auto w-full max-w-[480px] px-4 pb-20 pt-10 lg:pt-14">
  <section class="reveal mb-9 text-center" style="animation-delay: 40ms">
    <p class="mb-3 text-[11px] uppercase tracking-[0.22em] text-pink-200">Taiko Hoodi · testnet</p>
    <h1 class="display text-[34px] leading-[1.1] text-grey-10">
      Trade the <span class="text-pink-400">index</span> perp
    </h1>
    <p class="mx-auto mt-3 max-w-[22rem] text-sm leading-relaxed text-grey-200">
      Leveraged exposure to an option-basket index, ETH-margined, against a pooled LP vault.
    </p>
  </section>

  <NetworkGuard />

  <div class="space-y-5">
    <div class="reveal" style="animation-delay: 120ms">
      <MarketOverview market={$perpMarket} onRefresh={refresh} />
    </div>
  </div>
</main>

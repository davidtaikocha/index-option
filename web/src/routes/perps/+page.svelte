<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { account } from '$lib/stores';
  import { perpMarket, isPerpAdmin, myPositions } from '$lib/perpStores';
  import { readMarket, oracleAdmin, openPositionIds, readPosition } from '$lib/perp';
  import type { Address } from 'viem';
  import NetworkGuard from '$components/NetworkGuard.svelte';
  import MarketOverview from '$components/perp/MarketOverview.svelte';
  import OpenPositionCard from '$components/perp/OpenPositionCard.svelte';
  import PositionCard from '$components/perp/PositionCard.svelte';
  import LpVaultCard from '$components/perp/LpVaultCard.svelte';
  import LiquidationsCard from '$components/perp/LiquidationsCard.svelte';
  import PushPriceCard from '$components/perp/PushPriceCard.svelte';

  let timer: ReturnType<typeof setInterval> | undefined;

  async function refreshPositions() {
    if (!$account.address) {
      myPositions.set([]);
      return;
    }
    try {
      const ids = await openPositionIds($account.address as Address);
      const loaded = await Promise.all(ids.map((id) => readPosition(id)));
      myPositions.set(loaded.filter((p): p is NonNullable<typeof p> => p !== null));
    } catch {
      // keep prior positions on transient failure
    }
  }

  async function refresh() {
    try {
      perpMarket.set(await readMarket());
      await refreshPositions();
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
  $: if ($account.address !== undefined) refreshPositions();

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
    <div class="reveal" style="animation-delay: 200ms">
      <OpenPositionCard market={$perpMarket} onDone={refresh} />
    </div>
    {#each $myPositions as position (position.id)}
      <div class="reveal">
        <PositionCard {position} market={$perpMarket} onDone={refresh} />
      </div>
    {/each}
    <div class="reveal"><LpVaultCard market={$perpMarket} onDone={refresh} /></div>
    <div class="reveal"><LiquidationsCard market={$perpMarket} onDone={refresh} /></div>
    {#if $isPerpAdmin}
      <div class="reveal"><PushPriceCard market={$perpMarket} onDone={refresh} /></div>
    {/if}
  </div>
</main>

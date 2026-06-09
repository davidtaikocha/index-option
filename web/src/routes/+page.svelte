<script lang="ts">
  import { activeSeries } from '$lib/stores';
  import NetworkGuard from '$components/NetworkGuard.svelte';
  import SeriesSummary from '$components/SeriesSummary.svelte';
  import CreateSeriesCard from '$components/CreateSeriesCard.svelte';
  import MintCard from '$components/MintCard.svelte';
  import CombineCard from '$components/CombineCard.svelte';
  import PoolPanel from '$components/PoolPanel.svelte';
</script>

<div class="min-h-dvh">
  <main class="mx-auto w-full max-w-[480px] px-4 pb-20 pt-10 lg:pt-14">
    <section class="reveal mb-9 text-center" style="animation-delay: 40ms">
      <p class="mb-3 text-[11px] uppercase tracking-[0.22em] text-pink-200">Taiko Hoodi · testnet</p>
      <h1 class="display text-[34px] leading-[1.1] text-grey-10">
        Mint a <span class="text-pink-400">P / N</span> pair
      </h1>
      <p class="mx-auto mt-3 max-w-[22rem] text-sm leading-relaxed text-grey-200">
        Create an ETH-collateralized option series, split ETH into complementary P and N claims,
        and combine them back to ETH.
      </p>
    </section>

    <NetworkGuard />

    <div class="space-y-5">
      <div class="reveal" style="animation-delay: 120ms">
        <CreateSeriesCard />
      </div>

      {#if $activeSeries}
        <div class="reveal" style="animation-delay: 0ms">
          <SeriesSummary info={$activeSeries} />
        </div>
      {/if}

      <div class="reveal" style="animation-delay: 200ms">
        <MintCard />
      </div>

      <div class="reveal" style="animation-delay: 280ms">
        <CombineCard />
      </div>

      <div class="reveal" style="animation-delay: 320ms">
        <PoolPanel />
      </div>
    </div>

    <footer class="mt-10 text-center text-xs text-grey-500">
      <a
        class="transition-colors hover:text-pink-200"
        href="https://hoodi.taikoscan.io/address/0x32231734d2F09fAa3b6bE8c50D716a94f5519A88"
        target="_blank"
        rel="noreferrer">OptionFactory 0x3223…9A88 ↗</a>
    </footer>
  </main>
</div>

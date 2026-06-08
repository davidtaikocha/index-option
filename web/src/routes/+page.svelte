<script lang="ts">
  import { activeSeries } from '$lib/stores';
  import ConnectButton from '$components/ConnectButton.svelte';
  import NetworkGuard from '$components/NetworkGuard.svelte';
  import SeriesSummary from '$components/SeriesSummary.svelte';
  import CreateSeriesCard from '$components/CreateSeriesCard.svelte';
  import MintCard from '$components/MintCard.svelte';
  import CombineCard from '$components/CombineCard.svelte';
  import PoolPanel from '$components/PoolPanel.svelte';
</script>

<div class="min-h-dvh">
  <header
    class="sticky top-0 z-30 border-b border-grey-800/60 bg-grey-900/10 backdrop-blur-md">
    <div class="mx-auto flex max-w-2xl items-center justify-between px-4 py-4 lg:px-6 lg:py-5">
      <a href="/" class="flex items-center gap-3">
        <img src="/taiko-favicon.svg" alt="" class="h-8 w-8" />
        <span class="flex flex-col leading-tight">
          <span class="display text-lg text-grey-10">Index Options</span>
          <span class="text-[11px] uppercase tracking-[0.18em] text-grey-300">P / N primary market</span>
        </span>
      </a>
      <ConnectButton />
    </div>
  </header>

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

      {#if $activeSeries}
        <div class="reveal" style="animation-delay: 320ms">
          <PoolPanel info={$activeSeries} />
        </div>
      {/if}
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

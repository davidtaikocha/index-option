<script lang="ts">
  import { activeSeries } from '$lib/stores';
  import NetworkGuard from '$components/NetworkGuard.svelte';
  import SeriesSummary from '$components/SeriesSummary.svelte';
  import PoolPanel from '$components/PoolPanel.svelte';
</script>

<div class="min-h-dvh">
  <main class="mx-auto w-full max-w-[480px] px-4 pb-20 pt-10 lg:pt-14">
    <section class="reveal mb-9 text-center" style="animation-delay: 40ms">
      <p class="mb-3 text-[11px] uppercase tracking-[0.22em] text-pink-200">Taiko Hoodi · testnet</p>
      <h1 class="display text-[34px] leading-[1.1] text-grey-10">
        Trade <span class="text-pink-400">P / N</span>
      </h1>
      <p class="mx-auto mt-3 max-w-[22rem] text-sm leading-relaxed text-grey-200">
        Swap a series' complementary P and N claims, or provide liquidity, on the
        constant-product secondary market.
      </p>
    </section>

    <NetworkGuard />

    <div class="space-y-5">
      {#if $activeSeries}
        <div class="reveal" style="animation-delay: 0ms">
          <SeriesSummary info={$activeSeries} />
        </div>
      {/if}

      <div class="reveal" style="animation-delay: 120ms">
        <PoolPanel />
      </div>
    </div>
  </main>
</div>

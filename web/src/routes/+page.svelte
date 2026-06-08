<script lang="ts">
  import { activeSeries } from '$lib/stores';
  import ConnectButton from '$components/ConnectButton.svelte';
  import NetworkGuard from '$components/NetworkGuard.svelte';
  import SeriesSummary from '$components/SeriesSummary.svelte';
  import CreateSeriesCard from '$components/CreateSeriesCard.svelte';
  import MintCard from '$components/MintCard.svelte';
  import CombineCard from '$components/CombineCard.svelte';
</script>

<div class="min-h-dvh bg-base-100 text-base-content">
  <header class="border-b border-base-300">
    <div class="mx-auto flex max-w-2xl items-center justify-between px-4 py-4">
      <div class="flex flex-col">
        <span class="font-display text-xl text-primary">Index Options</span>
        <span class="text-xs text-base-content/60">P/N primary market · Taiko Hoodi</span>
      </div>
      <ConnectButton />
    </div>
  </header>

  <main class="mx-auto max-w-2xl space-y-6 px-4 py-8">
    <NetworkGuard />
    <CreateSeriesCard />
    {#if $activeSeries}
      <SeriesSummary info={$activeSeries} />
    {/if}
    <MintCard />
    <CombineCard />
  </main>
</div>

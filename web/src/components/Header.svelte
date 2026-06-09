<script lang="ts">
  import { page } from '$app/stores';
  import ConnectButton from '$components/ConnectButton.svelte';
  $: path = $page.url.pathname;
</script>

<header class="sticky top-0 z-30 border-b border-grey-800/60 bg-grey-900/10 backdrop-blur-md">
  <div class="mx-auto flex max-w-2xl items-center justify-between px-4 py-4 lg:px-6 lg:py-5">
    <a href="/" class="flex items-center gap-3">
      <img src="/taiko-favicon.svg" alt="" class="h-8 w-8" />
      <span class="flex flex-col leading-tight">
        <span class="display text-lg text-grey-10">Index Options</span>
        <span class="text-[11px] uppercase tracking-[0.18em] text-grey-300">Taiko Hoodi · testnet</span>
      </span>
    </a>
    <div class="flex items-center gap-2">
      <nav class="hidden gap-1 sm:flex">
        <a href="/" class="btn-soft px-3 py-1.5 text-xs {path === '/' ? '!border-pink-400 !text-grey-10' : ''}">Options</a>
        <a href="/perps" class="btn-soft px-3 py-1.5 text-xs {path.startsWith('/perps') ? '!border-pink-400 !text-grey-10' : ''}">Perps</a>
      </nav>
      <ConnectButton />
    </div>
  </div>
</header>

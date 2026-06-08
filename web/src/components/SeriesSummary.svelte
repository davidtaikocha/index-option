<script lang="ts">
  import type { SeriesInfo } from '$lib/stores';
  import { showToast } from '$lib/stores';
  import { explorerUrl } from '$lib/wagmi';
  import { shortenAddress } from '$lib/format';

  export let info: SeriesInfo;

  const rows = (): { label: string; addr: string }[] => [
    { label: 'Series', addr: info.series },
    { label: 'P token (pETHUSDC)', addr: info.pToken },
    { label: 'N token (nETHUSDC)', addr: info.nToken }
  ];

  async function copy(addr: string) {
    await navigator.clipboard.writeText(addr);
    showToast('info', 'Address copied');
  }
</script>

<div class="rounded-box bg-base-200 p-4 space-y-2">
  {#each rows() as row}
    <div class="flex items-center justify-between gap-2 text-sm">
      <span class="text-base-content/70">{row.label}</span>
      <span class="flex items-center gap-2">
        <a
          class="link link-primary font-mono"
          href={`${explorerUrl}/address/${row.addr}`}
          target="_blank"
          rel="noreferrer">{shortenAddress(row.addr)}</a
        >
        <button class="btn btn-ghost btn-xs" on:click={() => copy(row.addr)}>Copy</button>
      </span>
    </div>
  {/each}
</div>

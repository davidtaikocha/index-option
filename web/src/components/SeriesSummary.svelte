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
    try {
      await navigator.clipboard.writeText(addr);
      showToast('info', 'Address copied');
    } catch {
      showToast('error', 'Copy failed');
    }
  }
</script>

<div class="rounded-[16px] border border-grey-800 bg-grey-900/40 p-5 backdrop-blur-sm">
  <p class="mb-3.5 flex items-center gap-2 text-xs font-medium uppercase tracking-wider text-pink-200">
    <span class="status-dot bg-green-300 shadow-[0_0_8px_#47E0A0]"></span>
    Series created
  </p>
  <div class="space-y-3">
    {#each rows() as row}
      <div class="flex items-center justify-between gap-3 text-sm">
        <span class="text-grey-300">{row.label}</span>
        <span class="flex items-center gap-2">
          <a
            class="font-mono text-grey-100 transition-colors hover:text-pink-200"
            href={`${explorerUrl}/address/${row.addr}`}
            target="_blank"
            rel="noreferrer">{shortenAddress(row.addr)}</a>
          <button
            class="text-grey-500 transition-colors hover:text-pink-200"
            title="Copy address"
            aria-label="Copy address"
            on:click={() => copy(row.addr)}>
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <rect x="9" y="9" width="13" height="13" rx="2" />
              <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
            </svg>
          </button>
        </span>
      </div>
    {/each}
  </div>
</div>

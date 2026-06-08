<script lang="ts">
  import { toast } from '$lib/stores';

  const dot: Record<string, string> = {
    info: 'bg-pink-200 shadow-[0_0_8px_#FF6FC8]',
    success: 'bg-green-300 shadow-[0_0_8px_#47E0A0]',
    error: 'bg-red-300 shadow-[0_0_8px_#F15C5D]'
  };
</script>

{#if $toast}
  <div class="reveal fixed bottom-5 right-5 z-50 max-w-sm">
    <div
      class="flex items-start gap-3 rounded-[14px] border border-grey-800 bg-grey-900/85 px-4 py-3 text-sm shadow-[0_10px_48px_rgba(5,9,18,0.5)] backdrop-blur-md">
      <span class="status-dot mt-[5px] {dot[$toast.kind]}"></span>
      <span class="break-words text-grey-100">{$toast.message}</span>
    </div>
  </div>
{/if}

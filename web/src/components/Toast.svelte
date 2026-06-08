<script lang="ts">
  import { toast } from '$lib/stores';

  const styles: Record<string, string> = {
    info: 'alert-info',
    success: 'alert-success',
    error: 'alert-error'
  };
</script>

{#if $toast}
  <div class="toast toast-end z-50">
    <div class="alert {styles[$toast.kind]} max-w-md">
      <span class="break-words">{$toast.message}</span>
    </div>
  </div>
{/if}

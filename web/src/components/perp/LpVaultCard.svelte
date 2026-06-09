<script lang="ts">
  import { parseEther, type Address } from 'viem';
  import { account, showToast } from '$lib/stores';
  import type { PerpMarket } from '$lib/perp';
  import { vaultDeposit, vaultWithdraw, vaultShares } from '$lib/perp';
  import { decodePerpError } from '$lib/perpError';
  import { isPositiveDecimal, formatBalance } from '$lib/format';
  import { shareValue, poolPctBps } from '$lib/perpMath';

  export let market: PerpMarket | null;
  export let onDone: () => void = () => {};

  let tab: 'deposit' | 'withdraw' = 'deposit';
  let ethStr = '';
  let shareStr = '';
  let shares = 0n;
  let totalShares = 0n;
  let busy = false;

  async function refreshShares() {
    if (!$account.address) return;
    try {
      const r = await vaultShares($account.address as Address);
      shares = r.shares;
      totalShares = r.totalShares;
    } catch {
      // ignore transient read failures
    }
  }
  $: if ($account.address) refreshShares();

  $: myValue = market ? shareValue(shares, market.vaultAssets, totalShares) : 0n;
  $: pct = Number(poolPctBps(shares, totalShares)) / 100;

  async function onDeposit() {
    busy = true;
    try {
      await vaultDeposit(ethStr);
      showToast('success', 'Deposited to vault');
      ethStr = '';
      await refreshShares();
      onDone();
    } catch (e) {
      showToast('error', decodePerpError(e));
    } finally {
      busy = false;
    }
  }

  async function onWithdraw() {
    busy = true;
    try {
      await vaultWithdraw(parseEther(shareStr));
      showToast('success', 'Withdrew from vault');
      shareStr = '';
      await refreshShares();
      onDone();
    } catch (e) {
      showToast('error', decodePerpError(e));
    } finally {
      busy = false;
    }
  }
</script>

<section class="glass-card" data-glow-border>
  <div class="p-6 lg:p-7">
    <h2 class="display mb-5 text-lg text-grey-10">LP vault</h2>

    <div class="mb-4 grid grid-cols-2 gap-2 text-xs text-grey-300">
      <div class="rounded-[10px] border border-grey-700 bg-grey-900/30 px-3 py-2">Your value<br /><span class="font-mono text-grey-100">{formatBalance(myValue)} ETH</span></div>
      <div class="rounded-[10px] border border-grey-700 bg-grey-900/30 px-3 py-2">Pool share<br /><span class="font-mono text-grey-100">{pct.toFixed(2)}%</span></div>
    </div>
    {#if market}
      <p class="mb-4 text-xs text-grey-400">Vault free: <span class="font-mono text-grey-100">{formatBalance(market.vaultFree)} ETH</span> · reserved <span class="font-mono text-grey-100">{formatBalance(market.vaultReserved)} ETH</span></p>
    {/if}

    <div class="mb-4 flex gap-2">
      <button class="btn-soft flex-1 py-2 text-sm {tab === 'deposit' ? '!border-pink-400 !text-grey-10' : ''}" on:click={() => (tab = 'deposit')}>Deposit</button>
      <button class="btn-soft flex-1 py-2 text-sm {tab === 'withdraw' ? '!border-pink-400 !text-grey-10' : ''}" on:click={() => (tab = 'withdraw')}>Withdraw</button>
    </div>

    {#if tab === 'deposit'}
      <input class="input-box mb-3 px-3.5 py-2.5 text-sm" type="text" inputmode="decimal" bind:value={ethStr} placeholder="ETH amount" />
      <button class="btn-brand w-full py-2.5 text-sm" on:click={onDeposit} disabled={busy || !isPositiveDecimal(ethStr) || !$account.isConnected}>{busy ? 'Depositing…' : 'Deposit'}</button>
    {:else}
      <input class="input-box mb-3 px-3.5 py-2.5 text-sm" type="text" inputmode="decimal" bind:value={shareStr} placeholder="shares" />
      <p class="mb-3 text-xs text-grey-400">Your shares: <span class="font-mono text-grey-100">{formatBalance(shares)}</span> (withdraw is capped at the vault's free assets)</p>
      <button class="btn-brand w-full py-2.5 text-sm" on:click={onWithdraw} disabled={busy || !isPositiveDecimal(shareStr) || !$account.isConnected}>{busy ? 'Withdrawing…' : 'Withdraw'}</button>
    {/if}
  </div>
</section>

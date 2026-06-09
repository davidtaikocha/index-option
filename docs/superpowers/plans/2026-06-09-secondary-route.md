# Secondary Market Route Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the secondary market (`PoolPanel`) from a card on the Options page to its own `/secondary` route, added to the top bar as **Options · Secondary · Perps**.

**Architecture:** Pure SvelteKit routing/IA change. A new `/secondary` route renders the existing `PoolPanel` (+ `SeriesSummary` when a series is active); the shared in-memory `activeSeries` store carries the selection across routes, and `PoolPanel`'s built-in load-by-address handles cold entry. The Options page drops the panel and gains a discovery link. No chain logic, no new state, no contracts.

**Tech Stack:** SvelteKit (Svelte 4), Tailwind + DaisyUI. Verify with `npm run check` (svelte-check) and `npm run build` from `web/`.

**Spec:** `docs/superpowers/specs/2026-06-09-secondary-route-design.md`

---

## File structure

| File | Change |
|---|---|
| `web/src/components/Header.svelte` | add "Secondary" nav link between Options and Perps |
| `web/src/routes/secondary/+page.svelte` | **new** — hero + NetworkGuard + SeriesSummary (when active) + PoolPanel |
| `web/src/routes/+page.svelte` | remove `PoolPanel` (import + block); add a discovery link to `/secondary` |
| `web/src/components/PoolPanel.svelte` | one-line empty-state copy fix |

**Conventions:** the existing `/perps` route and `Header.svelte` are the templates. Page shell = `<div class="min-h-dvh"><main class="mx-auto w-full max-w-[480px] px-4 pb-20 pt-10 lg:pt-14">…`. Nav links are `btn-soft px-3 py-1.5 text-xs` with active class `!border-pink-400 !text-grey-10`. No component tests exist in this repo — verification is `npm run check` + `npm run build`. Run all web commands from `web/`.

---

## Task 1: Add "Secondary" to the top-bar nav

**Files:**
- Modify: `web/src/components/Header.svelte`

- [ ] **Step 1: Replace the file**

Overwrite `web/src/components/Header.svelte` with (only the `<nav>` gains a middle link):
```svelte
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
        <a href="/secondary" class="btn-soft px-3 py-1.5 text-xs {path.startsWith('/secondary') ? '!border-pink-400 !text-grey-10' : ''}">Secondary</a>
        <a href="/perps" class="btn-soft px-3 py-1.5 text-xs {path.startsWith('/perps') ? '!border-pink-400 !text-grey-10' : ''}">Perps</a>
      </nav>
      <ConnectButton />
    </div>
  </div>
</header>
```
Note: Options keeps the exact match `path === '/'` so it doesn't highlight on `/secondary` or `/perps`; the other two use `startsWith`.

- [ ] **Step 2: Typecheck**

Run: `cd web && npm run check`
Expected: 0 errors, 0 warnings.

- [ ] **Step 3: Commit**

```bash
git add web/src/components/Header.svelte
git commit -m "feat(web): add Secondary to top-bar nav"
```

---

## Task 2: Create the /secondary route

**Files:**
- Create: `web/src/routes/secondary/+page.svelte`

- [ ] **Step 1: Create the page**

`web/src/routes/secondary/+page.svelte`:
```svelte
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
```

- [ ] **Step 2: Typecheck + build**

Run: `cd web && npm run check && npm run build`
Expected: no errors; build succeeds (a `/secondary` route is emitted).

- [ ] **Step 3: Commit**

```bash
git add web/src/routes/secondary/+page.svelte
git commit -m "feat(web): /secondary route hosting the pool panel"
```

---

## Task 3: Trim the Options page + add a discovery link

**Files:**
- Modify: `web/src/routes/+page.svelte`

- [ ] **Step 1: Replace the file**

Overwrite `web/src/routes/+page.svelte` (drops the `PoolPanel` import + block; adds a discovery link before the footer):
```svelte
<script lang="ts">
  import { activeSeries } from '$lib/stores';
  import NetworkGuard from '$components/NetworkGuard.svelte';
  import SeriesSummary from '$components/SeriesSummary.svelte';
  import CreateSeriesCard from '$components/CreateSeriesCard.svelte';
  import MintCard from '$components/MintCard.svelte';
  import CombineCard from '$components/CombineCard.svelte';
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

      <div class="reveal text-center" style="animation-delay: 320ms">
        <a href="/secondary" class="text-sm text-pink-200 transition-colors hover:text-pink-100">
          Trade P / N on the Secondary market →
        </a>
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
```

- [ ] **Step 2: Typecheck**

Run: `cd web && npm run check`
Expected: 0 errors (no unused `PoolPanel` import remains).

- [ ] **Step 3: Commit**

```bash
git add web/src/routes/+page.svelte
git commit -m "feat(web): Options page is primary-market only + Secondary link"
```

---

## Task 4: Fix the PoolPanel empty-state copy

**Files:**
- Modify: `web/src/components/PoolPanel.svelte`

- [ ] **Step 1: Replace the empty-state line**

In `web/src/components/PoolPanel.svelte`, find:
```svelte
      <p class="mb-4 text-sm text-grey-300">Create a series above, or load one by address to trade its P / N pair.</p>
```
and replace with:
```svelte
      <p class="mb-4 text-sm text-grey-300">Create a series on the Options page, or load one by address to trade its P / N pair.</p>
```
(The panel is no longer rendered below `CreateSeriesCard`, so "above" is wrong.)

- [ ] **Step 2: Typecheck**

Run: `cd web && npm run check`
Expected: 0 errors.

- [ ] **Step 3: Commit**

```bash
git add web/src/components/PoolPanel.svelte
git commit -m "fix(web): PoolPanel empty-state points to the Options page"
```

---

## Task 5: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Typecheck + production build**

Run: `cd web && npm run check && npm run build`
Expected: 0 type errors; build succeeds with `/`, `/secondary`, and `/perps` routes.

- [ ] **Step 2: Existing tests still pass**

Run: `cd web && npm run test`
Expected: the existing `amm` / `format` / `perpMath` / `perpError` suites pass (this change adds no tests and touches no lib).

- [ ] **Step 3: Manual dogfood (optional, via `npm run dev` or `/browse`)**

Confirm: top bar shows **Options · Secondary · Perps** with the correct tab highlighted per route; Options no longer shows the secondary panel and shows the "Trade P / N on the Secondary market →" link; `/secondary` renders the panel, loads a series by address, and trades; creating a series on Options then navigating to Secondary preserves it.

---

## Self-review (completed by plan author)

**Spec coverage:** new `/secondary` route with hero + NetworkGuard + SeriesSummary(when active) + PoolPanel (§3) → T2; "Secondary" nav between Options and Perps with `startsWith('/secondary')` highlight and Options staying exact-match (§3, §5) → T1; remove PoolPanel from Options + discovery link (§3) → T3; PoolPanel copy fix (§3) → T4; shared `activeSeries` carries across routes / cold-load uses load-by-address (§4) → no code needed (store + existing PoolPanel behavior), exercised in T5 Step 3; check/build/tests (§6) → T5. All spec sections covered. No URL param / localStorage / mobile-nav work (explicitly out of scope in §2).

**Placeholder scan:** none — every step has complete file contents or an exact find/replace.

**Type consistency:** imports used in T2/T3 (`activeSeries`, `NetworkGuard`, `SeriesSummary`, `PoolPanel`, `CreateSeriesCard`, `MintCard`, `CombineCard`) all exist in the repo and match their `$components`/`$lib` paths; the `<SeriesSummary info={$activeSeries} />` prop matches its existing usage on the Options page; nav active-class strings match the existing `Header` pattern.

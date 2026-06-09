# Secondary Market Route — Design Spec

- **Date:** 2026-06-09
- **Status:** Approved (design); ready for implementation plan
- **Scope:** `web/` SvelteKit dapp — promote the secondary market to its own route + top-bar nav item

---

## 1. Context

The dapp's top bar currently has two routes: **Options** (`/`) and **Perps** (`/perps`). The
**secondary market** (`PoolPanel.svelte` — the constant-product AMM for trading a series' P/N
pair) lives as the last card on the Options page. This change promotes it to its own
**`/secondary`** route and adds it to the top bar, giving three pages:
**Options · Secondary · Perps**.

`activeSeries` is a shared in-memory Svelte store (`$lib/stores`) that survives client-side
navigation; `PoolPanel` already has a "load by address" entry and reloads when `activeSeries`
changes. No contracts or chain logic change.

## 2. Locked decisions

| Decision | Choice |
|---|---|
| New route | `/secondary` |
| Top-bar order & label | **Options · Secondary · Perps** (middle tab labelled "Secondary") |
| Series selection on the page | **Shared in-memory `activeSeries` store + `PoolPanel`'s existing load-by-address.** No URL param, no localStorage. |
| Options page after the move | Primary market only (Create · Summary · Mint · Combine) + a discovery link to Secondary |

### Out of scope
- Mobile nav: the top-bar `<nav>` is `hidden sm:flex` today (no nav on small screens). Pre-existing;
  not addressed here.
- URL-param / shareable pool links; localStorage persistence of the selected series.
- Any contract or `PoolPanel` behavior change beyond one copy fix.

## 3. Files

| File | Change |
|---|---|
| `web/src/routes/secondary/+page.svelte` | **New.** `<main>` with a hero ("Trade P / N · secondary market"), `<NetworkGuard/>`, `<SeriesSummary>` shown when `$activeSeries` is set, and `<PoolPanel/>`. Mirrors the existing page shell (narrow `max-w-[480px]` column, `reveal` animations). |
| `web/src/components/Header.svelte` | Insert `<a href="/secondary">Secondary</a>` between the Options and Perps links; active-highlight via `path.startsWith('/secondary')` (same `!border-pink-400 !text-grey-10` treatment as the others). |
| `web/src/routes/+page.svelte` | Remove the `<PoolPanel/>` block and its `import PoolPanel …` line. Add a small discovery link near the bottom of the card stack: "Trade P / N on the Secondary market →" pointing to `/secondary`. Keep everything else (hero, Create/Summary/Mint/Combine, footer). |
| `web/src/components/PoolPanel.svelte` | One-line copy fix in the `!activeSeries` empty state: change "Create a series **above**, or load one by address…" to "Create a series on the **Options** page, or load one by address…" (it is no longer below CreateSeries). |

## 4. Data flow

- `activeSeries` (writable store in `$lib/stores`) persists across SvelteKit client-side
  navigation. Creating/loading a series on Options carries into `/secondary`.
- Cold-loading `/secondary` or a hard refresh starts with `activeSeries === null` →
  `PoolPanel` renders its load-by-address / create-pool prompt (this already exists).
- `PoolPanel` reloads pool state whenever `activeSeries` changes and after each trade
  (`refresh()`), unchanged.

## 5. Edge cases

- **No wallet / wrong network:** reuse `<NetworkGuard/>` on the new page (same as other pages).
- **No active series:** `PoolPanel`'s existing empty state (with the corrected copy) prompts to
  load by address or create one on Options.
- **Settled series:** `PoolPanel` already freezes trading/funding — unchanged.
- **Active-link highlight:** Options uses exact match `path === '/'`; Secondary and Perps use
  `startsWith` so nested paths still highlight. (`/` must stay an exact match so it doesn't light
  up on every route.)

## 6. Testing

- No unit tests (pure UI/route move).
- `npm run check` (svelte-check) and `npm run build` must pass.
- Manual verification: top-bar shows three tabs with correct active highlight; Options no longer
  renders the secondary panel and shows the discovery link; `/secondary` renders `PoolPanel`,
  loads a series by address, and trades; navigating Options → Secondary preserves a created series.

## 7. Assumptions

- SvelteKit keeps `$lib/stores` alive across client-side navigation (standard behavior), so the
  shared `activeSeries` approach needs no extra wiring.
- This is a testnet research-prototype UI; no analytics/routing concerns beyond the above.

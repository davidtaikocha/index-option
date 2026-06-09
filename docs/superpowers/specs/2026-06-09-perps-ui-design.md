# Perps UI — Design Spec

- **Date:** 2026-06-09
- **Status:** Approved (design); ready for implementation plan
- **Scope:** `web/` SvelteKit dapp — add a Perps surface for the deployed Index Perp (Product A) contracts
- **Author:** Brainstormed with David (Taiko)

---

## 1. Context

The Index Perp contract stack (`IndexPerp`, `PerpVault`, `IndexBasket`, `PushOracle`,
`InsuranceFund`) is merged on `main` but **not yet deployed to Taiko Hoodi**, and the web app
(`web/`) currently only covers the P/N **Options** product (create series · mint P/N · combine ·
secondary AMM). This spec adds a **Perps** surface to the same dapp, reusing its design system
(DaisyUI + the custom Taiko glass-card theme), wallet plumbing (`@wagmi/core` + `viem`), and
conventions (`lib/contracts.ts`/`lib/pool.ts` for chain calls, `lib/amm.ts`(+test) for pure math).

This is a **research prototype on testnet**; the contracts are not audited.

## 2. Locked decisions

| Decision | Choice |
|---|---|
| Dependency handling | **Deploy the perp stack to Hoodi as part of this work** + add a manual owner/keeper **push-price** control in the UI (no separate keeper bot) |
| Flows covered | **Trade panel**, **market/index overview**, **LP vault**, **liquidations**, + admin push-price |
| Information architecture | **Dedicated `/perps` route** with a top **Options \| Perps** nav |
| Page layout | **Narrow single column** card stack (matches the existing ~480px app), mobile-first |
| Index level display | Show **both** the ETH-denominated index level **and** an implied ETH/USDC price (level→price inversion) when the basket is a single CALL leg |
| Pricing source | Read contract views where they exist; recompute funding/borrow **rates** and **liquidation level** client-side in `perpMath.ts` (mirror of `FundingMath`) |

### Out of scope (v1)
Price charts/history, multiple feeds or baskets, order types, notifications, bespoke mobile
polish beyond responsive stacking. No contract changes.

## 3. Prerequisite — deploy + initial price (one-time, scripted)

1. `forge script script/DeployIndexPerp.s.sol --rpc-url "$RPC_URL" --broadcast` (reads
   `PRIVATE_KEY`, optional `UPGRADE_ADMIN`/`KEEPER` from `.env`). Captures the 5 proxy addresses
   from the `console2` logs.
2. Push an initial price so `currentLevel()` is fresh:
   `cast send <PushOracle> "pushPrice(bytes32,uint256)" $(cast format-bytes32-string "ETHUSDC") 4000e18 --private-key …`
   (or via the new PushPriceCard once the UI is wired).
3. The deployer address becomes oracle `owner`/`keeper`, so the PushPriceCard will be visible to it.

**Surface the addresses for confirmation before committing them to `env.ts`.**

## 4. Architecture & file structure

The Perps surface is **self-contained** (own route, lib, components, stores) and reuses the
existing design system + wallet plumbing. The only edit to existing code is lifting the header
into the shared layout.

| File | Change | Purpose |
|---|---|---|
| `web/src/lib/env.ts` | edit | + `INDEX_PERP`, `PERP_VAULT`, `INDEX_BASKET`, `PUSH_ORACLE`, `INSURANCE_FUND`, `PERP_FEED_ID` (`stringToHex("ETHUSDC", { size: 32 })`), `PERP_DEPLOY_BLOCK` |
| `web/scripts/genAbi.mjs` | edit | + 5 targets → `lib/abi/{indexPerp,perpVault,indexBasket,pushOracle,insuranceFund}.ts` |
| `web/src/lib/abi/*.ts` | generated | the 5 perp ABIs (committed, like existing ABIs) |
| `web/src/lib/perp.ts` | new | wagmi read/write helpers for all perp contracts (see §5) |
| `web/src/lib/perpMath.ts` | new | pure derivations (see §6) |
| `web/src/lib/perpMath.test.ts` | new | vitest unit tests (mirrors `amm.test.ts`) |
| `web/src/lib/perpStores.ts` | new | perp market state + user position(s) |
| `web/src/lib/perpError.ts` | new | `decodePerpError()` — named-custom-error → readable message |
| `web/src/routes/+layout.svelte` | edit | render shared `Header.svelte` |
| `web/src/components/Header.svelte` | new | header lifted from `routes/+page.svelte` + `Options \| Perps` nav |
| `web/src/routes/+page.svelte` | edit | drop the inline header (now in layout); keep its hero |
| `web/src/routes/perps/+page.svelte` | new | the Perps page — narrow card stack |
| `web/src/components/perp/MarketOverview.svelte` | new | read-only index/market card |
| `web/src/components/perp/OpenPositionCard.svelte` | new | open long/short |
| `web/src/components/perp/PositionCard.svelte` | new | live position(s): PnL / liq / add-margin / close |
| `web/src/components/perp/LpVaultCard.svelte` | new | deposit/withdraw + share value |
| `web/src/components/perp/LiquidationsCard.svelte` | new | at-risk list + liquidate |
| `web/src/components/perp/PushPriceCard.svelte` | new | owner/keeper-only price push |

## 5. Data flow & `perp.ts` helpers

### Position discovery (no per-owner index on-chain)
`IndexPerp` stores `positions[id]` by incrementing id; there is **no** `positionsOf(owner)` view.
- **User positions:** `getLogs` for `Opened(id, owner, …)` (indexed `owner` → server-side filter)
  from `PERP_DEPLOY_BLOCK`, minus ids that later emitted `Closed(id, …)` or `Liquidated(id, …)`;
  each surviving id → `positions(id)`.
- **Liquidations:** same scan **without** the owner filter → global open-id set, ranked by health.
- Cache the user's last-opened id in `localStorage` as a fast path; events are the source of truth.
- If an RPC rejects the block range, chunk it (fallback only; single range is fine on testnet).

### Reads (all public views)
- Market: `basket.currentLevel()`, `perp.longOI()`, `perp.shortOI()`,
  `vault.totalAssets()`, `vault.reserved()`, `vault.maxUtilBps()`,
  `oracle.getSpotValue(PERP_FEED_ID) → (value, updatedAt)`, `basket.maxAge()`, `basket.feedId()`.
- Params for rate math: `perp.borrowBase()`, `perp.fundK()`, `perp.mmBps()`, `perp.openFeeBps()`,
  `perp.closeFeeBps()`, `perp.maxLeverage()`.
- Position: `perp.positions(id)`, `perp.equityOf(id, level)`, `perp.notionalOf(id)`.
- LP: `vault.sharesOf(addr)`, `vault.totalShares()`, `vault.freeAssets()`.
- Oracle admin: `oracle.keeper()`, `oracle.owner()`.

### Writes
- `perp.open{value: marginWei}(isLong, leverage1e18, limitLevel)`
- `perp.close(id, limitLevel)` · `perp.addMargin{value}(id)` · `perp.liquidate(id)`
- `vault.deposit{value}()` · `vault.withdraw(shares)`
- `oracle.pushPrice(PERP_FEED_ID, price1e18)`

### Refresh
Read-after-write (like `PoolPanel.refresh()`) plus a ~12s poll on the Perps page so level / PnL /
funding stay current.

## 6. `perpMath.ts` — pure derivations (unit-tested)

Constants `ONE = 10n**18n`, `BPS = 10000n`. All functions are pure (bigint in/out) so they can be
tested without a chain, mirroring `lib/amm.ts`.

- **Open preview:** `notional = leverage·margin/ONE`; `units = leverage·margin/level`;
  `openFee = notional·openFeeBps/BPS`; `marginNet = margin − openFee`.
- **Liquidation level** (equity is linear in level): with
  `maint = notional·mmBps/BPS` and `feesOwed = borrowOwed + fundOwed`,
  - long: `liqLevel = entry + ONE·(maint + feesOwed − margin)/units`
  - short: `liqLevel = entry − ONE·(maint + feesOwed − margin)/units`
  (clamp to `≥ 0`; if unreachable within the basket band, display "—").
- **Funding/borrow rates** (mirror `FundingMath`, per second, 1e18-scaled):
  - `util = reserved ≥ assets ? ONE : reserved·ONE/assets`; `borrowRate = borrowBase·util/ONE`.
  - `skew = totalOI==0 ? 0 : (longOI−shortOI)·ONE/totalOI`; `fundingRate = fundK·skew/ONE`.
  - Present as %/hour for readability (`rate·3600`).
- **Level ↔ price inversion** (single CALL leg `K`, weight 1): `level = 1 − K/x` ⇒
  `x = K·ONE/(ONE − level)`. Only used when `basket` has exactly one CALL leg of weight `ONE`;
  otherwise show level only.
- **LP share value:** `shareValueEth = totalShares==0 ? 0 : shares·(assets + VIRTUAL)/(totalShares + VIRTUAL)`
  where `VIRTUAL = 1e6` (matches `PerpVault`); `poolPct = shares·BPS/totalShares`.
- **Slippage bound:** long open/close `limit = level·(ONE ± tolBps/BPS)`; default `tolBps = 50` (0.5%).

## 7. Components

All use `glass-card`/`btn-brand`/`btn-soft`/`input-box`/`pill` styles, `showToast`, and the
`account`/`NetworkGuard` stores/components.

1. **Header.svelte** (in layout) — logo, `Options | Perps` segmented links (active highlight via
   `$page.url.pathname`), `ConnectButton`.
2. **perps/+page.svelte** — hero ("Perps · index on options"), `NetworkGuard`, then the card stack:
   MarketOverview → OpenPositionCard → PositionCard (if any) → LpVaultCard → LiquidationsCard →
   PushPriceCard (admin only). Light ~12s poll drives refresh.
3. **MarketOverview** — index level (+ implied ETH/USDC price), funding rate, borrow rate,
   long/short OI, vault TVL & utilization, **freshness badge** ("live Ns ago" / "stale — push a
   price"). On `currentLevel()` revert (stale), still shows last `getSpotValue` value + age.
4. **OpenPositionCard** — long/short toggle, margin (ETH), leverage slider 1–20× + numeric,
   live est. entry / liq (level + price) / notional / open fee, collapsible slippage tolerance
   (default 0.5%), "Open long/short". Disabled off-network / stale oracle / invalid input /
   `notional > vault free·maxUtil`.
5. **PositionCard** — lists open position(s): side · leverage · units, entry, mark, **PnL**
   (colored), liq (level + price), margin, funding+borrow owed; "Add margin" (input) and "Close"
   (slippage-guarded). Empty state when none.
6. **LpVaultCard** — Deposit/Withdraw tabs (like `LiquidityForm`): ETH → shares / shares → ETH
   (withdraw capped at free assets); shows your shares, share value (ETH), your % of pool,
   free vs reserved.
7. **LiquidationsCard** (collapsible) — at-risk open positions (id, owner short, side, equity vs
   maintenance, health bar) + per-row "Liquidate" (earns keeper reward); empty state otherwise.
8. **PushPriceCard** (admin) — visible only when connected address `== oracle.keeper()` or
   `oracle.owner()`. Input ETH/USDC price → `pushPrice`; shows last pushed value + time.

## 8. Error handling & edge cases

- **Stale/zero oracle:** MarketOverview catches `currentLevel()` revert, falls back to
  `getSpotValue` for last value/age, renders the stale state; OpenPositionCard disabled while stale.
- **No wallet / wrong network:** reuse `NetworkGuard` + disabled-with-hint pattern.
- **No position:** PositionCard empty state.
- **Client-side pre-checks** (avoid most reverts): leverage ≤ `maxLeverage`, margin > 0,
  `notional ≤ vault free·maxUtilBps`, withdraw ≤ free assets, liquidate only shown when
  `equity < maintenance`.
- **`decodePerpError()`** maps named custom errors (`SlippageExceeded`, `UtilizationExceeded`,
  `InsufficientFreeAssets`, `NotLiquidatable`, `Unauthorized`, `LeverageTooHigh`, `ZeroMargin`,
  `StalePrice`, `ZeroPrice`) to friendly toasts via the perp ABIs, instead of raw `(e).message`.
- **Event-scan bounds:** from `PERP_DEPLOY_BLOCK`; chunk on RPC range errors (fallback only).
- **Formatting:** reuse `lib/format.ts`; add level (4dp), %/hour, and ETH helpers as needed.

## 9. Testing

- **`perpMath.test.ts`** (vitest) is the automated coverage: liq-level closed form (long/short)
  reconciled against the equity formula; funding/borrow rate mirror vs `FundingMath`;
  level↔price inversion; units/notional/fee; LP share value with the virtual offset; slippage bound.
- **`npm run check` (svelte-check) + `npm run build` + `npm run test`** must all pass.
- **On-chain flows** (open→close PnL, add margin, liquidate, LP deposit/withdraw, push price,
  stale state) verified against the live Hoodi deploy; dogfood with the `/browse` skill after wiring.

## 10. Assumptions & open questions

- **Deploy is a prerequisite** of this work; the implementation plan begins with deploy + address
  capture + ABI generation before any component is wired.
- **Single basket/feed** (the seed `CALL@2000`); the level→price inversion is gated to a single
  CALL leg of weight `ONE` and otherwise hidden.
- **`equityOf` uses last-poked accumulators** (no `_poke()` in a view), so displayed equity/PnL
  slightly understates accrued fees — acceptable for display.
- **Admin gating** reads `oracle.keeper()`/`owner()`; if the connected wallet isn't the deployer,
  the PushPriceCard is hidden (price must be pushed out-of-band for the index to stay fresh).
- **No contract changes**; if a missing view turns out to be needed (e.g., a per-owner position
  index for cheaper discovery), that would be a separate contract-side follow-up, not part of this
  UI spec.

# P/N Secondary-Market AMM — Design

- **Date:** 2026-06-08
- **Status:** Approved design, pending implementation plan
- **Scope:** A set-aware constant-product AMM (Gnosis FPMM-style) that acts as a secondary market for the `P`/`N` claim tokens of an `OptionSeries`, plus a swap + liquidity UI in the existing dapp, deployed to Taiko Hoodi.

## 1. Context

The repo implements the P/N option primitive from
[Building index-tracking assets on top of options instead of debt](https://ethresear.ch/t/building-index-tracking-assets-on-top-of-options-instead-of-debt/25036/).
Each `OptionSeries` is ETH-backed and exposes two `ClaimToken`s (standard ERC20-like:
`approve`/`transfer`/`transferFrom`/`allowance`, 18 decimals):

- `split(receiver)` — deposit ETH, mint equal `P` and `N`.
- `combine(amount, receiver)` — burn equal `P` + `N`, return ETH (allowed until settlement).
- `settle()` — after maturity, read the oracle and fix `payoutP`/`payoutN` (summing to exactly `1e18`).
- `redeemP` / `redeemN` — after settlement, burn claims for ETH.

The option contracts are now **UUPS-upgradeable** (`OwnableUpgradeable` + `UUPSUpgradeable`);
`OptionFactory` deploys an ERC1967 proxy per series from a shared `seriesImplementation`.

The key identity this design exploits: **`P + N = 1 ETH` is pinned by `split`/`combine` arbitrage
until settlement.** That makes a P/N AMM fundamentally different from a generic token pool — we
build *with* the identity instead of fighting it.

## 2. Goal & non-goals

**Goal:** A set-aware AMM where a single ETH-denominated pool provides deep liquidity for buying and
selling **both** `P` and `N` by minting/redeeming complete sets through `OptionSeries.split`/`combine`,
plus a UI for swapping and providing liquidity, deployed to Taiko Hoodi.

**Architecture chosen:** set-aware FPMM (one ETH-integrated pool per series). Rejected alternatives:
- **Two independent `P/ETH` + `N/ETH` pools** — ignores the identity: idle ETH, fragmented
  liquidity, double IL, needs external arbitrage to stay consistent.
- **Pure `P↔N` pool + ETH router** — economically identical to the chosen design, but splits it into
  two contracts; we prefer the single ETH-integrated pool to match the existing one-contract-per-market
  topology and give the cleanest UX.

**Non-goals (v1):**
- No `withdrawToETH` convenience (LPs withdraw raw P/N and combine/redeem themselves).
- No TWAP price accumulator for external consumers.
- No multi-series router or concentrated liquidity.
- **Hard non-goal:** the pool price must never feed the series' settlement oracle (circular and
  flash-manipulable).

## 3. Components & topology

```
OptionPoolFactory (UUPS proxy)        OptionPool (UUPS proxy, one per series)     OptionSeries (1 change)
  poolImplementation                    reserves Rp (P), Rn (N)  ── split ─────▶   split() guard:
  createPool(series) ──────────────▶    LP shares (internal ERC20-like)            maturity → settlement
  mapping series⇒pool (no dups)         swap / fund / withdraw  ◀── combine ──
  emits PoolCreated                     reads series.settled(), payoutP/N
```

- **`OptionPool`** — set-aware FPMM for a single series. Persistent state is only the two reserves
  `Rp`, `Rn` (tracked in **storage**, Uniswap-V2 style — not `balanceOf` — so donations/skims cannot
  move price) plus LP shares. Has a `receive()` to accept ETH returned by `combine`. Reads
  `series.settled()` to gate trading. `ReentrancyGuardUpgradeable`, `OwnableUpgradeable`,
  `UUPSUpgradeable`. The pool trusts exactly the `series` and its two `ClaimToken`s (P, N), all fixed
  at `initialize`; callers and ETH receivers are untrusted.
- **`OptionPoolFactory`** — UUPS factory mirroring `OptionFactory`. Holds `poolImplementation`,
  deploys one canonical pool proxy per series via `createPool(series)`, keeps `mapping(series ⇒ pool)`
  to prevent duplicates, emits `PoolCreated(series, pool, pToken, nToken)`. `setPoolImplementation`
  (owner) for future pool upgrades.
- **LP shares** — tracked as a minimal internal ERC20-like ledger in the pool (balances + total
  supply, transferable), following the `ClaimToken` pattern. No separate token contract in v1.

## 4. Upstream change to `OptionSeries`

The only edit to the reviewed primitive: in `split()`, replace the maturity guard with a settlement
guard so `split` is symmetric with `combine`.

- Replace `if (block.timestamp >= maturity) revert SplitAfterMaturity();` with
  `if (settled) revert SplitAfterSettlement();`.
- Rename the error `SplitAfterMaturity` → `SplitAfterSettlement`.

**Safety rationale:** minting a complete set for 1 ETH is always fair — `P + N` redeems to exactly
1 ETH right up until settlement binds the payouts — so this carries the same justification that
already allows `combine` after maturity.

**Shipping it (UUPS):** deploy a new `OptionSeries` implementation with the relaxed guard and call
`factory.setSeriesImplementation(newImpl)`. New series created after that point get the relaxed
`split`. The already-deployed series keeps the old guard (not individually upgraded in v1); the live
demo creates a fresh series through the re-pointed factory. The relax is only consequential in the
maturity→settlement window.

**Test impact:** `testSplitRejectedAtMaturity` becomes `testSplitAllowedAfterMaturityBeforeSettlement`,
plus a new `testSplitRejectedAfterSettlement`. The full existing suite must still pass.

## 5. Swap & LP math

Constant product on the two reserves: `Rp · Rn = k`. Implied price of P in ETH =
`Rn / (Rp + Rn)`; `price(P) + price(N) = 1` falls out automatically.

### Buy P with `e` ETH (no fee)

1. `series.split{value: e}` → reserves become `(Rp + e, Rn + e)`.
2. Pay the user `outP = (Rp + e) − k / (Rn + e)`, where `k = Rp · Rn` (taken before the split).
3. Pool keeps the leftover N; price of P ticks up. N-side buys are symmetric.

### Sell `inP` P for ETH (no fee)

1. User sends `inP` P into the pool (pulled via `transferFrom`; the UI does the `approve` first).
2. Redeem `r` complete sets, where `r` solves `(Rp + inP − r)(Rn − r) = k`:
   `r = [ (A + Rn) − sqrt((A + Rn)² − 4 (A·Rn − k)) ] / 2`, with `A = Rp + inP` (smaller root;
   `r < Rn` always, so reserves stay strictly positive).
3. `series.combine(r, user)` → user receives `r` ETH.

### Fees

A per-pool fee (default **30 bps**, owner-settable, capped at a sane max e.g. 1%), taken on the input.
The pool mints/redeems the full set (no idle ETH) but computes the user's output along the curve using
the **fee-discounted** input; the undisbursed remainder stays in reserves, raising `k` for all LPs
pro-rata. Integer rounding favors the pool.

### Slippage protection

Every swap takes a `minAmountOut` argument and reverts if the computed output is below it (and the UI
sets a tolerance). This is an addition to the original spec.

## 6. LP lifecycle

### Fund (add liquidity)

- LP sends `e` ETH → pool `split`s it into `e` P + `e` N.
- **First funder** sets the starting price via a distribution hint (target price `p0`): the pool keeps
  `Rp:Rn` at the implied ratio and **returns the excess of the heavier side** to the funder. Mints the
  initial `L` shares.
- **Later funders** add at the current reserve ratio; the excess side is returned; `L` minted pro-rata
  to contribution.

### Withdraw (remove liquidity)

- Burn `L` shares → receive **pro-rata raw P and N** (non-custodial; identical mechanics before and
  after settlement).
- The LP combines the matched portion → ETH and/or redeems at fixed payouts themselves.
- `withdrawToETH` (auto-combine matched portion, return residual side) is explicitly **out of v1**.

## 7. Settlement wind-down

- The pool reads `series.settled()`. Once true: **`swap` and `fund` revert; only `withdraw` stays open.**
- The pool never calls `settle()` — settlement is driven externally on the series; the pool only
  observes the flag, and never feeds the settlement oracle.
- Post-settlement, withdrawing LPs receive pro-rata P and N and redeem each at the fixed
  `payoutP`/`payoutN`. Because `payoutP + payoutN = 1e18` and the pool only ever held
  complete-set-derived reserves, **the pool is always solvent for every LP claim**.
- **Accepted cost (the "freeze at settlement" decision):** during the maturity→settlement window,
  informed traders can swap against converging-but-not-final prices. Fees are the LP's compensation;
  this is a bounded informational risk, never a solvency risk.

## 8. Safety

- **Reentrancy:** the pool calls `series.split` (payable), `series.combine` (sends ETH back to the
  pool), and sends ETH to users. The series and P/N tokens are trusted (fixed at init); the ETH
  receiver is not. Enforce **CEI + `ReentrancyGuardUpgradeable`**; update reserves before any external
  ETH send.
- **Rounding:** integer constant-product always rounds **in favor of the pool/LPs** (user gets floor,
  pool keeps dust), so `k` is non-decreasing across swaps and value cannot be extracted by fragmenting
  trades. Series-level redemption dust is already bounded by the existing remainder carry.
- **Reserve positivity:** the sell quadratic guarantees `r < Rn`, so neither reserve can be drained to
  zero by a valid trade.
- **Reserves vs balances:** reserves are storage values synced on each operation, so token donations
  cannot shift price (Uniswap-V2 discipline).

## 9. Secondary-market UI (`web/`)

A new section added to the existing SvelteKit dapp in the same bridge-ui visual system, gated to the
active series (from the primary-market flow) or a loaded series address.

- **Pool discovery:** read `factory.poolOf(series)`. If no pool exists, a one-click **Create pool**
  (`factory.createPool(series)`), then surface the pool.
- **Trade panel:** select side (P or N) and direction (buy/sell), enter the input amount (ETH for buy,
  tokens for sell). Show a **live quote**, the current spot price, and **min received** at the chosen
  slippage tolerance. For sells, an `approve` step (P/N → pool) precedes `swap(minOut)`. Refresh
  balances and reserves after.
- **Liquidity panel:** **Fund** (ETH amount → LP shares; first-funder price hint) and **Withdraw**
  (LP amount → raw P and N, with a note to combine/redeem). Shows pool reserves, your LP share, and
  your pooled P/N.
- **Reads:** reserves, `price(P)`/`price(N)`, your LP balance, your P/N balances, allowances — via
  pool view functions (`getReserves`, `quoteBuy`, `quoteSell`, `spotPrice`).
- **Lib:** new `contracts.ts` helpers (getPool/createPool, reserves+quotes, buy/sell with `minOut`,
  fund, withdraw, approvals); `POOL_FACTORY` added to `env.ts`. Vitest for the quote/slippage/share
  math helpers.

## 10. Deployment & migration

- Deploy a new `OptionSeries` implementation (split relax) and call
  `factory.setSeriesImplementation(newImpl)` so new series get the relaxed `split`.
- Deploy `OptionPool` implementation + `OptionPoolFactory` implementation + the factory ERC1967 proxy
  on Taiko Hoodi (a `DeployPoolFactory.s.sol` script mirroring `Deploy.s.sol`).
- Add `POOL_FACTORY` to `.env`/`.env.example` and to `web/src/lib/env.ts`.
- Extend the live Vercel app (`index-option-ui`).
- The already-deployed series keeps the old `split` guard; the live demo creates a fresh series through
  the re-pointed factory, then a pool for it.

## 11. Testing strategy

All Solidity tests run against `MockPriceOracle`; no fork needed.

- **Unit:** buy/sell P and N math; fee accrual to LPs; first-funder price hint; proportional funding;
  withdraw before/after settlement; settlement freeze (`swap`/`fund` revert, `withdraw` open); the
  relaxed `split` window (`testSplitAllowedAfterMaturityBeforeSettlement`,
  `testSplitRejectedAfterSettlement`); `minAmountOut` reverts; factory deployment + duplicate
  prevention + events; UUPS upgrade authorization for pool and factory.
- **Invariant / fuzz:**
  - `k` is non-decreasing across any swap sequence.
  - No sequence of swaps extracts value (round-trip never profits).
  - Reserves stay strictly positive.
  - `price(P) + price(N) = 1` holds within rounding.
  - **Pool solvency:** the sum of all LP claims is always redeemable from reserves.
- **Web:** vitest for the quote/slippage/share-math helpers; production build; browser smoke of the
  trade + liquidity panels.

## 12. v1 scope

**In:** `OptionPool` (UUPS set-aware FPMM: swap with `minOut`, fund, withdraw, settlement freeze,
configurable fee), `OptionPoolFactory` (UUPS), the one `OptionSeries.split` relax (new impl +
re-point), the secondary-market UI (trade + liquidity), deployment to Hoodi + live Vercel ship, and the
full unit + invariant suite.

**Out (future):** `withdrawToETH`, TWAP accumulator, multi-series router, concentrated liquidity,
per-proxy upgrade of already-deployed series.

## 13. Decisions log

| Decision | Choice | Rationale |
| --- | --- | --- |
| AMM architecture | Set-aware FPMM (one ETH-integrated pool per series) | Most capital-efficient given `P + N = 1`; no idle ETH; matches existing topology; cleanest UX. |
| Maturity/settlement transition | Freeze at **settlement** (not maturity) | Captures the extra trading window; convergence sniping is paid for by fees and is not a solvency risk. |
| Split availability | Relax `split` to **pre-settlement**, shipped as a new UUPS impl | Restores buy/sell symmetry for the AMM; safe because `P + N` redeems to 1 ETH until payouts bind. |
| LP withdrawal asset | Raw P and N (no auto-ETH) | Non-custodial and simplest; identical before/after settlement. |
| Fee | 30 bps default, owner-settable, retained as reserves | Standard AMM fee; retaining as reserves keeps the no-idle-ETH invariant. |
| Slippage | `minAmountOut` on every swap | Protects users from sandwiching/price moves; standard AMM safety. |
| New contracts upgradeability | UUPS (pool + pool factory) | Consistency with the now-upgradeable `OptionFactory`/`OptionSeries`. |
| UI scope | Swap + liquidity (fund/withdraw) | An AMM needs LPs to function; full secondary-market surface. |
| LP share token | Minimal internal ERC20-like ledger in the pool | Simplest; no separate token contract needed in v1. |

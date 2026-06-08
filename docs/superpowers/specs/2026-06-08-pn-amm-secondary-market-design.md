# P/N Secondary-Market AMM — Design

- **Date:** 2026-06-08
- **Status:** Approved design, pending implementation plan
- **Scope:** A Uniswap-style (constant-product) AMM that acts as a secondary market for the `P`/`N` claim tokens of an `OptionSeries`.

## 1. Context

The repo implements the P/N option primitive from
[Building index-tracking assets on top of options instead of debt](https://ethresear.ch/t/building-index-tracking-assets-on-top-of-options-instead-of-debt/25036/).
Each `OptionSeries` is ETH-backed and exposes two `ClaimToken`s:

- `split(receiver)` — deposit ETH, mint equal `P` and `N`.
- `combine(amount, receiver)` — burn equal `P` + `N`, return ETH (allowed until settlement).
- `settle()` — after maturity, read the oracle and fix `payoutP`/`payoutN` (summing to exactly `1e18`).
- `redeemP` / `redeemN` — after settlement, burn claims for ETH.

The key identity this design exploits: **`P + N = 1 ETH` is pinned by `split`/`combine` arbitrage until settlement.** That makes a P/N AMM fundamentally different from a generic token pool — we build *with* the identity instead of fighting it.

## 2. Goal & non-goals

**Goal:** A set-aware AMM (Gnosis FPMM-style) where a single ETH-denominated pool provides deep liquidity for buying and selling **both** `P` and `N` at once, by minting/redeeming complete sets through `OptionSeries.split`/`combine`.

**Non-goals (v1):**
- No `withdrawToETH` convenience (LPs withdraw raw P/N and combine/redeem themselves).
- No TWAP price accumulator for external consumers.
- No multi-series router or concentrated liquidity.
- **Hard non-goal:** the pool price must never feed the series' settlement oracle (circular and flash-manipulable).

## 3. Approach: set-aware FPMM

Chosen over (a) independent `P/ETH` + `N/ETH` pools and (b) a pure `P↔N` pool, because the set-aware design gives ETH in/out liquidity for both sides from one pool while holding **no idle ETH** — ETH is transient within a transaction:

- **Buy** P: incoming ETH is `split` into a complete set added to reserves; the user receives P out.
- **Sell** P: incoming P is paired with reserve N and `combine`d back to ETH on the way out.

The pool's persistent state is only the two reserves `Rp` (P) and `Rn` (N), plus LP shares.

## 4. Components & topology

```
OptionPoolFactory          OptionPool (one per series)        OptionSeries (existing, 1 change)
  createPool(series) ─────▶  reserves: Rp (P), Rn (N)  ◀──────  split()  [relaxed to pre-settlement]
  mapping series→pool        LP shares (ERC20-like)             combine()
  emits PoolCreated          swap / fund / withdraw             settled() / payoutP / payoutN
```

- **`OptionPool`** — FPMM for a single series. Holds only P and N as reserves. Tracks LP shares as a minimal ERC20-like token (reuse the `ClaimToken` pattern). Reads `series.settled()` to gate trading. Has a `receive()` to accept ETH from `combine`.
- **`OptionPoolFactory`** — deploys one canonical pool per series, `mapping(series ⇒ pool)` to prevent duplicates, emits `PoolCreated`. Mirrors the existing `OptionFactory`.

The pool trusts exactly two things, both fixed at construction: the `series` and its two `ClaimToken`s (P, N). Callers and ETH receivers are untrusted.

## 5. Upstream change to `OptionSeries`

The only edit to the reviewed primitive: in `split()`, replace the maturity guard with a settlement guard so `split` is symmetric with `combine`.

- Replace `if (block.timestamp >= maturity) revert SplitAfterMaturity();` with `if (settled) revert SplitAfterSettlement();`.
- Rename the error `SplitAfterMaturity` → `SplitAfterSettlement`.

**Safety rationale:** minting a complete set for 1 ETH is always fair — `P + N` redeems to exactly 1 ETH right up until settlement binds the payouts — so this carries the same justification that already allows `combine` after maturity. It is arguably *more* consistent with the article's logic.

**Test impact:** `testSplitRejectedAtMaturity` becomes `testSplitAllowedAfterMaturityBeforeSettlement`, plus a new `testSplitRejectedAfterSettlement`. The full existing suite must still pass.

## 6. Swap mechanics & math

Constant product on the two reserves: `Rp · Rn = k`. Implied price of P in ETH = `Rn / (Rp + Rn)`; `price(P) + price(N) = 1` falls out automatically.

### Buy P with `e` ETH (no fee)

1. `series.split{value: e}` → reserves become `(Rp + e, Rn + e)`.
2. Pay the user `outP` such that the product is preserved:

   `outP = (Rp + e) − k / (Rn + e)`     where `k = Rp · Rn`

3. Pool keeps the leftover N; price of P ticks up. (N-side buys are symmetric.)

### Sell `inP` P for ETH (no fee)

1. User sends `inP` P into the pool.
2. Redeem `r` complete sets, where `r` solves `(Rp + inP − r)(Rn − r) = k`:

   `r = [ (A + Rn) − sqrt((A + Rn)² − 4 (A·Rn − k)) ] / 2`,  with `A = Rp + inP`

   (smaller root; `r < Rn` always, so reserves stay strictly positive).
3. `series.combine(r, user)` → user receives `r` ETH.

### Fees

A configurable per-pool fee (default 0.3%), taken on the input. The pool mints/redeems the full set (no idle ETH) but computes the user's output along the curve using the **fee-discounted** input; the undisbursed remainder stays in reserves, raising `k` for all LPs pro-rata. Exact integer rounding favors the pool. (This differs from Gnosis, which parks fees as idle collateral; retaining them as reserves keeps our no-idle-ETH invariant.)

## 7. LP lifecycle

### Fund (add liquidity)

- LP sends `e` ETH → pool `split`s it into `e` P + `e` N.
- **First funder** sets the starting price via a distribution hint: the pool keeps `Rp:Rn` at the target ratio and **returns the excess of the heavier side** to the funder (so funding at price 0.7 leaves them holding the directional remainder — exactly Gnosis `addFunding`). Mints `L` shares.
- **Later funders** add at the current reserve ratio; excess side returned; `L` minted pro-rata to contribution.

### Withdraw (remove liquidity)

- Burn `L` shares → receive **pro-rata raw P and N** (non-custodial; identical mechanics before and after settlement).
- The LP combines the matched portion → ETH and/or redeems at fixed payouts themselves.
- `withdrawToETH` (auto-combine matched portion, return residual side) is explicitly **out of v1**.

## 8. Settlement wind-down

- The pool reads `series.settled()`. Once true: **`swap` and `fund` revert; only `withdraw` stays open.**
- The pool never calls `settle()` — settlement is driven externally on the series; the pool only observes the flag.
- Post-settlement, withdrawing LPs receive pro-rata P and N and redeem each at the fixed `payoutP`/`payoutN`. Because `payoutP + payoutN = 1e18` and the pool only ever held complete-set-derived reserves, **the pool is always solvent for every LP claim** — no unbacked shares.
- **Accepted cost (the "freeze at settlement" decision):** during the maturity→settlement window, informed traders can swap against converging-but-not-final prices. Fees are the LP's compensation; this is a bounded informational risk, never a solvency risk.

## 9. Safety

- **Reentrancy:** the pool calls `series.split` (payable), `series.combine` (sends ETH back to the pool), and sends ETH to users. The series and P/N tokens are trusted (fixed at construction); the ETH receiver is not. Enforce **CEI + a `nonReentrant` guard**; update reserves before any external ETH send.
- **Rounding:** integer constant-product always rounds **in favor of the pool/LPs** (user gets floor, pool keeps dust), so `k` is non-decreasing across swaps and value cannot be extracted by fragmenting trades. Series-level redemption dust is already bounded by the existing remainder carry.
- **Reserve positivity:** the sell quadratic guarantees `r < Rn`, so neither reserve can be drained to zero by a valid trade.

## 10. Testing strategy

All tests run against `MockPriceOracle`; no fork needed.

- **Unit:** buy/sell P and N math; fee accrual to LPs; first-funder price hint; proportional funding; withdraw before/after settlement; settlement freeze (`swap`/`fund` revert, `withdraw` open); the relaxed `split` window; factory deployment + duplicate prevention + events.
- **Invariant / fuzz:**
  - `k` is non-decreasing across any swap sequence.
  - No sequence of swaps extracts value (round-trip never profits).
  - Reserves stay strictly positive.
  - `price(P) + price(N) = 1` holds within rounding.
  - **Pool solvency:** the sum of all LP claims is always redeemable from reserves.

## 11. v1 scope

**In:** `OptionPool` (set-aware FPMM: swap, fund, withdraw, settlement freeze), `OptionPoolFactory`, the one `OptionSeries.split` relax, full unit + invariant suite.

**Out (future):** `withdrawToETH`, TWAP accumulator, multi-series router, concentrated liquidity.

## 12. Decisions log

| Decision | Choice | Rationale |
| --- | --- | --- |
| Primary job of the AMM | Set-aware pool (both P and N from one ETH pool) | Most capital-efficient given `P + N = 1`; no idle ETH. |
| Maturity/settlement transition | Freeze at **settlement** (not maturity) | Captures the extra trading window; convergence sniping is paid for by fees and is not a solvency risk. |
| Split availability | Relax `split` to **pre-settlement** | Restores buy/sell symmetry for the AMM; safe because `P + N` redeems to 1 ETH until payouts are bound. |
| LP withdrawal asset | Raw P and N (no auto-ETH) | Non-custodial and simplest; identical before/after settlement. |

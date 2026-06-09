# Index Perp (Product A) — Contract Design Spec

- **Date:** 2026-06-09
- **Status:** Approved (design); ready for implementation plan
- **Scope:** Smart contracts only, "functional v1" fidelity, Taiko Hoodi testnet
- **Author:** Brainstormed with David (Taiko)

---

## 1. Context

This repo deploys an ETH-collateralized **P/N option primitive** (`OptionSeries` + `ClaimToken`)
and a per-series constant-product secondary market (`OptionPool`), based on
[Building index-tracking assets on top of options instead of debt](https://ethresear.ch/t/building-index-tracking-assets-on-top-of-options-instead-of-debt/25036/).

A prior research pass concluded the protocol needs two complementary products to get
traffic and be profitable on Taiko:

- **A — Index Perp:** an oracle-priced perpetual giving leveraged exposure to an
  option-basket index. Needs no underlying spot liquidity, so it works on a near-empty
  chain. **This spec.**
- **B — Perpetual Options:** a rolling-series wrapper that removes the strike/expiry
  fragmentation of `OptionSeries`/`OptionPool`. **Separate, later spec** that reuses
  A's oracle, funding math, and insurance fund.

This document specifies **A only**. B will be a much smaller spec because A builds the
shared foundation.

### What the P/N primitive actually is (grounding)

For a series with strike `K` and resolved ETH/USDC price `x` (both 1e18):

- `payoutP = min(1, K/x)` ETH per P token → USD value `min(x, K)` = **covered call** (ETH capped at K).
- `payoutN = 1 − payoutP` ETH per N token → USD value `max(x − K, 0)` = **call option @ K**.
- `P + N = 1 ETH` collateral, always fully prefunded, never liquidatable.

An "option-based index" is a weighted basket of such legs whose ETH value is a
deterministic function of `x`. The Index Perp lets traders take leveraged long/short
exposure to that value, priced purely from an ETH/USDC oracle.

---

## 2. Locked decisions

| Decision | Choice | Rationale |
|---|---|---|
| Fidelity | **Functional v1** | Full funding accumulator, maintenance-margin liquidation (manually callable), parameterized baskets, basic insurance fund; mock-but-realistic oracle. Not audited; testnet. |
| Denomination & margin | **ETH-denominated index + ETH margin** | Consistent with the ETH-collateralized primitive; no stablecoin sourcing on Taiko; no quanto. |
| Counterparty | **Pooled LP vault (GMX/HLP-style)** | LP vault is the house and IS the TVL; works with one-sided flow on an empty chain. |
| Pricing | **Oracle-execution** (fill at IndexNAV, no AMM mark) | Coherent with pooled LP; no manipulable AMM mark under one-sided flow. |
| NAV source | **Deterministic intrinsic replication from oracle spot only** | Unmanipulable; does not touch the thin P/N pool. |
| Oracle staleness | **System pauses** (state-changing ops revert) until a fresh price is pushed | Simplicity + safety for v1. |
| LP exposure reserve | **`reserve = 1 × notional` + utilization cap**; extreme moves beyond reserve draw the insurance fund | Simple, adequate for a prototype. |

The primitive contracts (`OptionSeries`, `ClaimToken`, `OptionPool`, `OptionFactory`,
`OptionPoolFactory`) are **not modified**.

---

## 3. Architecture

```
                 ┌──────────────┐   getSpotValue()        ┌─────────────┐
                 │  PushOracle  │◄────────────────────────│ IndexBasket │
 keeper push ───►│ (live + res) │                         │ levelEth(x) │
                 └──────┬───────┘                         └──────┬──────┘
                        │ spot (x, updatedAt)                    │ currentLevel()
                        ▼                                        ▼
   trader ETH  ┌───────────────────────────────────────────────────────┐
   ───────────►│                     IndexPerp                          │
   open/close/ │  positions • _poke() funding/borrow accumulators       │
   addMargin/  │  open · close · addMargin · liquidate                  │
   liquidate   └───┬───────────────────────┬───────────────────┬───────┘
                   │ reserve/release         │ payProfit/takeLoss │ coverShortfall
                   ▼ pay/take                 ▼                    ▼
            ┌──────────────┐          (LP capital +        ┌────────────────┐
            │  PerpVault   │           realized fees/pnl)  │ InsuranceFund  │
            │ ETH LP house │                               │ ETH bad-debt   │
            └──────────────┘                               └────────────────┘
```

### Contract list (all UUPS unless noted; mirror existing `Initializable + OwnableUpgradeable + UUPSUpgradeable + ERC1967Proxy + script` pattern)

| # | Contract | Responsibility | Depends on | Type |
|---|---|---|---|---|
| 1 | `ILivePriceOracle` | `getSpotValue(feedId) → (value, updatedAt)` live ETH/USDC | — | interface |
| 2 | `PushOracle` | owner/keeper-pushed price; implements **both** `ILivePriceOracle` and the existing `IPriceOracle.getResolvedValue` (can also settle series, replacing the EOA oracle) | — | UUPS |
| 3 | `IndexBasket` | stores legs `{kind, strike, weight}`; pure `levelEth(spot)`; owner-configurable; validates level positivity | — | UUPS |
| 4 | `PerpVault` | ETH LP vault (deposit/withdraw → mint/burn shares); tracks `reserved`; utilization cap | — | UUPS + ReentrancyGuard |
| 5 | `IndexPerp` | position lifecycle; holds funding/borrow accumulators; fills at oracle level | 2,3,4,6,7 | UUPS + ReentrancyGuard |
| 6 | `FundingMath` | pure library: cumulative borrow + skew funding (per-second) | — | library |
| 7 | `InsuranceFund` | ETH backstop for bad debt; owner-governed | — | UUPS |

**Out of scope for v1 (future):** multi-index factory (v1 wires a single set via a deploy
script), price-impact fee, keeper automation (liquidation/funding callable manually),
physical hedge vault holding real P/N (v1 is purely synthetic), and Product B.

---

## 4. Component specs

### 4.1 `ILivePriceOracle` / `PushOracle`

```solidity
interface ILivePriceOracle {
    /// @return value 1e18 USDC per ETH; @return updatedAt push timestamp.
    function getSpotValue(bytes32 feedId) external view returns (uint256 value, uint256 updatedAt);
}
```

`PushOracle`:
- `pushPrice(bytes32 feedId, uint256 value)` — `onlyKeeper`; stores `value` + `block.timestamp`; reverts `ZeroPrice` on 0.
- `getSpotValue` returns stored `(value, updatedAt)`. Staleness is enforced by the *consumer* (`IndexBasket.currentLevel` / `IndexPerp`) against its `maxAge`, so the oracle stays a dumb data source.
- Implements `IPriceOracle.getResolvedValue(series)` so it can also resolve `OptionSeries`, letting the team retire the single EOA oracle `0x5f2b…60AA`.
- `setKeeper`, `owner` via `OwnableUpgradeable`.

### 4.2 `IndexBasket`

```solidity
enum LegKind { CAPPED, CALL, ETH_SPOT }     // CAPPED = P, CALL = N
struct IndexLeg { LegKind kind; uint256 strike; int256 weight; }  // strike,weight 1e18

function levelEth(uint256 x) public view returns (uint256);       // Σ wᵢ·ethPayoffᵢ(x)
function currentLevel() external view returns (uint256);          // levelEth(freshSpot)
function setLegs(IndexLeg[] calldata legs) external onlyOwner;    // re-validates positivity
```

Per-leg ETH payoff at spot `x` (reusing `OptionSeries` formulas exactly):

| kind | `ethPayoff(x)` (1e18) |
|---|---|
| `CAPPED` (P) | `x ≤ strike ? ONE : strike·ONE/x` |
| `CALL` (N) | `x ≤ strike ? 0 : ONE − strike·ONE/x` |
| `ETH_SPOT` | `ONE` |

- `levelEth = Σ wᵢ · ethPayoffᵢ` (signed weights; negative = short leg).
- Config-time validation samples the level across a configured price band `[xLo, xHi]`
  and reverts `NonPositiveLevel` if it is ever `≤ 0`; reverts `EmptyBasket` / `BadLeg`
  (e.g. zero strike on a CAPPED/CALL leg).
- `currentLevel()` reads `getSpotValue`, reverts `StalePrice` if `updatedAt + maxAge < now`
  or `ZeroPrice` if `value == 0`.

### 4.3 `PerpVault`

ETH LP house. Holds **only** LP capital + realized fees/PnL (trader margins live in `IndexPerp`).

```solidity
function deposit() external payable returns (uint256 shares);     // shares = e·totalShares/balance (first: shares=e)
function withdraw(uint256 shares) external returns (uint256 eth); // requires eth ≤ freeAssets = balance − reserved
// onlyPerp:
function reserve(uint256 amount) external;     // reserved += amount; require reserved ≤ balance·maxUtilBps/BPS
function release(uint256 amount) external;     // reserved −= amount
function payProfit(address to, uint256 amount) external;  // vault → trader
function takeLoss() external payable;          // trader loss → vault (balance up)
```

- `freeAssets = balance − reserved`; `reserved` cannot be withdrawn by LPs.
- Share price = `balance / totalShares`; fees and trader losses raise it, trader profits lower it.
- `ReentrancyGuard` on `deposit`/`withdraw`; `EthTransferFailed` on payouts.

### 4.4 `FundingMath` (pure library) + accumulator state in `IndexPerp`

`_poke()` runs at the start of every state-changing op:

```
dt   = now − lastPoke
util = min(ONE, reserved / vaultAssets)
borrowCum  += BORROW_BASE · util / ONE · dt                    // ETH per ETH-notional, ≥ 0
skew        = totalOI == 0 ? 0 : (longOI − shortOI) · ONE / totalOI   // signed
fundingCum += FUND_K · skew / ONE · dt                          // signed; longs pay when > 0
lastPoke    = now
```

`borrowCum` is `uint256` monotonic; `fundingCum` is `int256`. Positions snapshot both at
open and settle the delta at close/liquidation.

### 4.5 `IndexPerp`

```solidity
struct Position {
    address owner; bool isLong;
    uint256 units;            // 1e18 index units
    uint256 entryLevel;       // 1e18 ETH/unit
    uint256 marginEth;
    uint256 entryBorrowCum;
    int256  entryFundingCum;
    uint64  openedAt;
}
// notional = units · entryLevel / ONE   (ETH)

function open(bool isLong, uint256 leverage, uint256 limitLevel) external payable returns (uint256 posId);
function close(uint256 posId, uint256 limitLevel) external returns (int256 pnlEth);
function addMargin(uint256 posId) external payable;
function liquidate(uint256 posId) external returns (uint256 penalty);
```

**open(isLong, leverage, limitLevel)** payable — `leverage` is 1e18-scaled (e.g. 5x = `5e18`, 1.5x = `1.5e18`).
```
level = currentLevel(); _poke()
require isLong ? level ≤ limitLevel : level ≥ limitLevel       // SlippageExceeded
require leverage ≤ maxLeverage                                 // LeverageTooHigh (maxLeverage also 1e18-scaled)
require msg.value > 0                                          // ZeroMargin
units    = leverage · msg.value / level         // 1e18 units;  units·level/ONE = notional
notional = leverage · msg.value / ONE           // ETH = leverage × margin
openFee  = notional · openFeeBps / BPS
margin   = msg.value − openFee
vault.takeLoss{value: openFee}()                              // fee → LP (minus protocol cut, v1: all LP)
vault.reserve(notional)                                       // reverts UtilizationExceeded
(isLong ? longOI : shortOI) += notional
store Position{ ..., entryBorrowCum, entryFundingCum }
```

**close(posId, limitLevel)**
```
require msg.sender == pos.owner                                // NotOwner
level = currentLevel(); _poke()
require isLong ? level ≥ limitLevel : level ≤ limitLevel       // SlippageExceeded
pnl        = isLong ? units·(level−entryLevel)/ONE : units·(entryLevel−level)/ONE   // signed
borrowOwed = notional · (borrowCum − entryBorrowCum) / ONE                          // ≥ 0
fundOwed   = (isLong ? +1 : −1) · notional · (fundingCum − entryFundingCum) / ONE   // signed
closeFee   = (units · level / ONE) · closeFeeBps / BPS
settle     = int(margin) + pnl − int(borrowOwed) − fundOwed − int(closeFee)
// vault delta: receives (−pnl) + borrowOwed + closeFee; funding nets trader↔trader, residual → vault
vault.release(notional); (isLong ? longOI : shortOI) −= notional
if settle > 0: pay trader settle  (profit portion via vault.payProfit; margin portion from IndexPerp)
else:          settle = 0; draw shortfall from InsuranceFund to keep vault whole
delete position (mark closed)
```

**addMargin(posId)** payable → `pos.marginEth += msg.value` (improves health).

**liquidate(posId)**
```
level = currentLevel(); _poke()
equity = int(margin) + pnl − int(borrowOwed) − fundOwed
require equity < int(notional · mmBps / BPS)                   // NotLiquidatable
penalty = notional · liqPenaltyBps / BPS
split penalty → keeper reward (msg.sender) + InsuranceFund
close at level; trader gets max(0, equity − penalty); shortfall → InsuranceFund (emit BadDebt)
```

### 4.6 `InsuranceFund`

```solidity
function deposit() external payable;
function coverShortfall(address to, uint256 amount) external; // onlyPerp; sends min(amount, balance); emits BadDebt(uncovered) if short
function withdraw(uint256 amount, address to) external onlyOwner;  // surplus
```

### 4.7 Parameters (owner-set, each bounded by a hard constant)

`maxLeverage, openFeeBps, closeFeeBps, BORROW_BASE, FUND_K, mmBps, liqPenaltyBps,
maxUtilBps, maxAge`. Every setter reverts `ParamOutOfBounds` past its constant ceiling so
governance cannot brick or rug the system.

---

## 5. Error handling

| Contract | Errors / guards |
|---|---|
| `PushOracle` | `ZeroPrice`, `Unauthorized` |
| `IndexBasket` | `EmptyBasket`, `BadLeg`, `NonPositiveLevel`, `StalePrice`, `ZeroPrice` |
| `PerpVault` | `ZeroAmount`, `InsufficientFreeAssets`, `InsufficientShares`, `OnlyPerp`, `EthTransferFailed` |
| `IndexPerp` | `ZeroMargin`, `LeverageTooHigh`, `UtilizationExceeded`, `SlippageExceeded`, `NotOwner`, `PositionClosed`, `NotLiquidatable` |
| `InsuranceFund` | `OnlyPerp`, (Ownable) |
| Common | `ParamOutOfBounds`, `EthTransferFailed`, `ReentrancyGuard` on all state-changing fns, `_poke()` first in every state-changing op |

---

## 6. Security invariants

1. **Solvency:** the protocol never pays ETH it does not have. Any shortfall beyond
   `margin + vault freeAssets` is routed to `InsuranceFund` and emits `BadDebt`; never a
   silent failure.
2. `PerpVault.balance ≥ reserved` at all times; LPs can never withdraw `reserved` capital.
3. ETH held by `IndexPerp` equals the sum of open-position margins (modulo in-flight call).
4. No position can extract more than `vault freeAssets + its own margin`.
5. Accumulators are monotonic (`borrowCum`) / consistently signed (`fundingCum`); position
   settlement uses only the delta since open.
6. Owner/governance is bounded: every parameter has a hard constant ceiling.

---

## 7. Testing matrix (Foundry, mirror existing `TestBase` / mocks)

| # | File | Coverage |
|---|---|---|
| 1 | `IndexBasket.t` | three leg payoffs at `x<K / x=K / x>K`; multi-leg weights; level-positivity validation; **reconcile against `OptionSeries.settle` formulas** |
| 2 | `PushOracle.t` | push/read spot; staleness revert (consumer side); `getResolvedValue` for series; access control |
| 3 | `PerpVault.t` | deposit/withdraw share math; reserved not withdrawable; `onlyPerp`; first depositor; pay/take/reserve/release accounting |
| 4 | `IndexPerpOpen.t` | units/notional/fee math; leverage cap; utilization cap; OI + accumulator snapshots; `limitLevel` slippage |
| 5 | `IndexPerpClose.t` | long/short PnL; borrow + funding + close fee deduction; profit from vault / loss to vault; slippage; reserve release; OI decrement |
| 6 | `Funding.t` | skew sign (long-heavy → longs pay); borrow scales with utilization; `vm.warp` time accrual; long/short netting |
| 7 | `Liquidation.t` | maintenance breach detection; penalty split (keeper/insurance); shortfall → insurance; `NotLiquidatable` revert; `BadDebt` event |
| 8 | `InsuranceFund.t` | partial cover; `BadDebt` event; owner withdraw surplus |
| 9 | `*Upgradeability.t` | UUPS upgrade + auth per upgradeable contract (mirror existing `OptionUpgradeability`) |
| 10 | `IndexPerpFuzz.t` | open→close **ETH conservation** (vault + trader + insurance + fees net 0 ± dust); accumulator monotonicity; withdraw never exceeds free |
| 11 | `Solvency.invariant` | `vault.balance ≥ reserved`; IndexPerp ETH == Σ margins; no position extracts more than vault-free + own margin |

---

## 8. Deployment wiring (v1, script not factory)

A `DeployIndexPerp.s.sol` script deploys + wires one set: `PushOracle`, one `IndexBasket`
(seeded with an example basket, e.g. a 1-leg `CALL@K` and/or a 2-leg call-spread),
`InsuranceFund`, `PerpVault`, `IndexPerp` (referencing the four), and grants `onlyPerp`
roles. Reads `PRIVATE_KEY`, `UPGRADE_ADMIN`, `KEEPER`, `FEED_ID`, basket params from env,
mirroring the existing `Deploy.s.sol` / `DeploySeries.s.sol` pattern.

---

## 9. Assumptions & open questions

- **Testnet vs mainnet:** repo currently targets Taiko Hoodi testnet (chain 167013); the
  original ask referenced mainnet. This spec is chain-agnostic; deploy target is a config.
- **Mock-but-realistic oracle:** v1 uses `PushOracle` driven by an off-chain keeper. A
  decentralized adapter (Pyth/RedStone/Chainlink) is a v2 swap-in behind `ILivePriceOracle`.
- **Funding/borrow constants** (`BORROW_BASE`, `FUND_K`, fee bps, `mmBps`, `liqPenaltyBps`,
  `maxUtilBps`, `maxLeverage`, `maxAge`) need initial values; to be set in the plan as
  named constants with conservative defaults.
- **Protocol fee cut:** v1 routes all fees to LPs; a protocol treasury cut is a trivial
  later parameter.
- New perp/liquidation/funding code is unaudited; run the `solidity-auditor` skill before
  any non-testnet use.

---

## 10. Follow-on: Product B (separate spec)

`PerpetualOption` rolling-series wrapper + keeper roll (before `OptionSeries` settlement),
charging streaming premium to holders paid to writers/LPs — consolidating the
strike/expiry ladder into one perpetual instrument. Reuses `PushOracle`, `FundingMath`,
and `InsuranceFund` from this spec. To be brainstormed after A is implemented.

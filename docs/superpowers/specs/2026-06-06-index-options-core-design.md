# Index Options Core Design

## Purpose

Build a Foundry prototype of the core ETH-backed option primitive described in Vitalik Buterin's EthResearch post, "Building index-tracking assets on top of options instead of debt." The prototype implements only the base P/N option market. It does not implement an automated index-tracking wrapper, DAO rebalancer, production oracle, or market-making system.

The goal is to model a slow-oracle synthetic option where each minted P/N pair is fully backed by ETH and can never require liquidation. Before settlement, one P plus one N recombine into one unit of ETH collateral. After settlement, P and N independently redeem against complementary payout ratios whose sum is one.

## Scope

In scope:

- Fresh Solidity/Foundry project.
- Core option series factory.
- One option series contract per market.
- One ERC20 P token and one ERC20 N token per option series.
- Oracle abstraction through an interface.
- Mock oracle implementation for tests.
- Unit tests for lifecycle, payout math, and failure cases.

Out of scope:

- Automated index-tracking wrapper.
- Rebalancing strategy.
- Real oracle integrations.
- Dispute or escalation flow.
- AMM or market-maker integration.
- Production deployment scripts beyond what is useful for local testing.

## Units

`strike` and resolved oracle value `x` use 18-decimal fixed-point values denominated in ETH terms for ticker `T`.

The settlement formula is:

```solidity
payoutP = min(1e18, strike * 1e18 / x);
payoutN = 1e18 - payoutP;
```

Each deposited wei mints one unit of P and one unit of N. P and N are 18-decimal ERC20 tokens, so token amounts align with ETH wei amounts.

## Architecture

### `IPriceOracle`

`IPriceOracle` is the oracle boundary used by an option series. The interface exposes whether a series is resolved and the resolved value `x`. The option series treats `x == 0` as invalid.

The first implementation uses a mock oracle in tests. The production-facing contract code depends only on the interface.

### `OptionFactory`

`OptionFactory` creates option series from:

- ticker label
- strike
- maturity timestamp
- oracle address
- P token metadata
- N token metadata

The factory emits an event for each created series and returns the deployed series address.

### `OptionSeries`

`OptionSeries` owns the ETH collateral for one option market. It deploys or owns two claim tokens: P and N.

Responsibilities:

- Accept ETH deposits through `split`.
- Mint equal P and N balances to the requested receiver.
- Burn equal P and N balances through `combine` before settlement and return ETH.
- Settle once after maturity by reading the oracle.
- Burn P or N after settlement and send the corresponding ETH payout.

The contract stores immutable market parameters: ticker, strike, maturity, oracle, P token, and N token. It stores settlement state once resolved: `payoutP`, `payoutN`, and resolved oracle value `x`.

### `ClaimToken`

`ClaimToken` is a minimal ERC20 used for P and N claims. Mint and burn are restricted to the owning `OptionSeries`. Users interact with the token as a normal ERC20 for transfer and approval.

## Lifecycle

### Open

Before maturity, users call `split(receiver)` with ETH. The series mints equal P and N token amounts to `receiver`.

Users can call `combine(amount, receiver)` before settlement. The series burns `amount` P and `amount` N from the caller and sends `amount` ETH to `receiver`.

### Matured But Unresolved

After maturity, new splits are disabled to keep the maturity boundary clean.

Combining remains allowed until settlement because P plus N still maps exactly to one unit of ETH collateral while no oracle value has been bound.

### Resolved

After maturity, a caller can settle the series if the oracle reports a resolved value. Settlement can happen only once.

After settlement:

- `redeemP(amount, receiver)` burns P and sends `amount * payoutP / 1e18` ETH.
- `redeemN(amount, receiver)` burns N and sends `amount * payoutN / 1e18` ETH.
- `combine` is disabled.
- `split` remains disabled.

Any tiny ETH dust caused by integer division remains in the series. Tests assert that dust is bounded.

## Error Handling

Use custom Solidity errors for explicit failure modes:

- zero strike
- zero maturity
- zero oracle address
- zero amount
- split after maturity
- combine after settlement
- settle before maturity
- oracle unresolved
- oracle resolved with `x == 0`
- settle twice
- redeem before settlement
- failed ETH transfer

ERC20 balance and allowance failures are handled by the token implementation.

## Testing

The Foundry test suite covers:

- Factory deploys a valid option series and emits the expected event.
- `split` mints equal P and N and stores ETH collateral.
- `combine` burns equal P and N and returns ETH before settlement.
- Splits are rejected after maturity.
- Settlement is rejected before maturity.
- Settlement is rejected when the oracle is unresolved.
- Settlement is rejected when `x == 0`.
- Duplicate settlement is rejected.
- Settlement below strike gives P a payout of `1e18` and N a payout of `0`.
- Settlement at strike gives P a payout of `1e18` and N a payout of `0`.
- Settlement above strike splits collateral by `strike / x`.
- P and N redemptions independently burn claims and pay the expected ETH.
- Combined redemptions drain expected collateral with only bounded integer-division dust.
- `combine` remains allowed after maturity but before settlement.
- `combine` is rejected after settlement.

## Design Rationale

The prototype uses one self-contained `OptionSeries` per market because it keeps collateral accounting local and legible. Each series owns its P/N tokens and ETH balance, so a reader can verify the no-liquidation invariant without inspecting global factory state.

The prototype uses ERC20 P/N token pairs rather than ERC1155 claims because each option side should be easy to inspect, transfer, and eventually connect to liquidity tooling. ERC1155 could reduce deployment overhead in a many-series system, but the added indirection is not useful for the first research prototype.

The oracle is only an interface because the core primitive should not depend on a specific oracle or dispute mechanism. The mock oracle exists to make settlement behavior testable.

## Acceptance Criteria

The implementation is complete when:

- The directory contains a working Foundry project.
- `forge test` passes.
- The contracts implement the lifecycle and payout behavior described above.
- The code has no dependency on a concrete oracle outside tests.
- The base P/N primitive is implemented without wrapper or rebalancing logic.

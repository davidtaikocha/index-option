# Index Options

Foundry prototype for ETH-collateralized ETH/USDC P/N option claims, based on the idea in
[Building index-tracking assets on top of options instead of debt](https://ethresear.ch/t/building-index-tracking-assets-on-top-of-options-instead-of-debt/25036/).

The project implements the core P/N option primitive only for ETH/USDC. It does not include an automated index wrapper, AMM, rebalancer, real oracle integration, dispute process, or production deployment flow.

## Concept

Each option series is backed by ETH collateral and settles against an ETH/USDC oracle price. It has two claim tokens:

- `P`: the protected or capped upside side.
- `N`: the complementary side.

Before settlement, one P plus one N can always be recombined into one unit of ETH collateral. After maturity, the series reads a resolved oracle value `x` and fixes two complementary payout ratios:

```solidity
payoutP = min(1e18, strike * 1e18 / x);
payoutN = 1e18 - payoutP;
```

Token amounts align with wei. Depositing `1 wei` mints `1` P unit and `1` N unit.

## Contracts

### `ClaimToken`

Minimal ERC20-like claim token used for P and N claims.

- 18 decimals.
- Standard transfer, approval, and allowance behavior.
- Minting and burning are restricted to the owning `OptionSeries`.
- No external dependencies.

### `OptionSeries`

Self-contained ETH/USDC option market for one strike, maturity, and oracle.

Main lifecycle:

1. `split(receiver)`: before maturity, deposits ETH and mints equal P/N claims.
2. `combine(amount, receiver)`: before settlement, burns equal P/N claims and returns ETH.
3. `settle()`: after maturity, reads the oracle and fixes P/N payouts.
4. `redeemP(amount, receiver)` and `redeemN(amount, receiver)`: after settlement, burns claims and pays ETH.

Safety details:

- `combine` and redemption validate receivers before burning claims.
- Settlement rejects unresolved or zero oracle values.
- `strike` and claim amounts are bounded so fixed-point multiplication cannot overflow.
- P/N payouts sum to `1e18`, so settled claims cannot overpay collateral.
- Fractional redemption remainders are carried globally per side to avoid accumulating one floor-division dust unit per redemption call.

### `OptionFactory`

Stateless factory that deploys `OptionSeries` contracts and emits the deployed series plus P/N token addresses.

### `IPriceOracle`

Small oracle interface that returns the resolved ETH/USDC price:

```solidity
function getResolvedValue(address series) external view returns (bool resolved, uint256 value);
```

The core contracts depend only on this interface. Tests use `MockPriceOracle`.

## Development

Install Foundry, then run:

```bash
forge test -vvv
```

Format Solidity:

```bash
forge fmt
```

Check whitespace:

```bash
git diff --check
```

## Test Coverage

The test suite covers:

- Restricted mint/burn and ERC20-like transfer behavior.
- Splitting ETH into equal P/N claims.
- Combining equal P/N claims before settlement.
- Maturity and lifecycle guards.
- Oracle settlement below, at, and above strike.
- Independent P/N redemption.
- Zero receiver handling before burns.
- Fixed-point overflow guards.
- Fragmented redemption dust handling.
- Factory deployment, event contents, and constructor error propagation.

## Status

Research prototype. Not audited. Do not use with real funds.

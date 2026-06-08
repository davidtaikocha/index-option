# ETH/USDC Hardcoded Series Design

## Context

The current prototype already uses native ETH as collateral and models the
payoff with an ETH/USDC-style price: tests deploy `"USD/ETH"` series with
strikes such as `2000e18` and oracle values such as `2500e18`. The remaining
generality is mostly in deployment metadata: `ticker`, P/N token names, P/N
symbols, and the corresponding factory event fields are caller supplied.

For this prototype, ETH/USDC is the only supported market. The contract surface
should reflect that directly.

## Goals

- Make every deployed series an ETH-collateralized ETH/USDC option series.
- Reduce constructor and factory inputs to the parameters that still vary per
  series: strike, maturity, and oracle.
- Preserve the existing P/N accounting, settlement math, lifecycle guards,
  overflow bounds, receiver validation, and redemption dust handling.
- Rename comments, docs, and tests away from generic ticker/index language where
  ETH/USDC semantics are clearer.

## Non-Goals

- Do not add ERC20 collateral or USDC settlement. Collateral remains native ETH.
- Do not add automated wrappers, rolling/perpetual rebalancing, AMMs, funding,
  liquidation, dispute, or production oracle logic.
- Do not make the factory store global oracle configuration yet.
- Do not remove safety checks just because the product is hardcoded.

## Approach

Use a hardcoded ETH/USDC product surface while keeping each series independently
configured by strike, maturity, and oracle.

`OptionSeries` constructor changes from:

```solidity
constructor(
    string memory ticker_,
    uint256 strike_,
    uint256 maturity_,
    address oracle_,
    string memory pName_,
    string memory pSymbol_,
    string memory nName_,
    string memory nSymbol_
)
```

to:

```solidity
constructor(uint256 strike_, uint256 maturity_, address oracle_)
```

The contract should no longer store caller-provided `ticker`. Do not add a new
pair-selection API; the market pair is defined by the contract implementation
and documentation.

P/N `ClaimToken` instances are deployed with fixed ETH/USDC names and symbols,
using these exact values:

```solidity
new ClaimToken("Protected ETH/USDC", "pETHUSDC");
new ClaimToken("Complement ETH/USDC", "nETHUSDC");
```

`OptionFactory.createSeries` changes from eight parameters to:

```solidity
function createSeries(uint256 strike, uint256 maturity, address oracle)
    external
    returns (address seriesAddress)
```

The factory event should drop `ticker`, token-name, and token-symbol data. It
should still emit the deployed series address, strike, maturity, oracle, and P/N
token addresses.

## Data Flow

The runtime lifecycle remains unchanged:

1. A user calls `split(receiver)` with ETH.
2. The series mints equal P and N claim amounts to `receiver`.
3. Before settlement, the holder can call `combine(amount, receiver)` to burn
   equal P/N claims and receive ETH back.
4. After maturity, `settle()` reads the ETH/USDC oracle price for the series.
5. `redeemP(amount, receiver)` and `redeemN(amount, receiver)` burn settled
   claims and pay ETH according to complementary payout ratios.

Settlement math remains:

```solidity
payoutP = min(1e18, strike * 1e18 / ethUsdcPrice);
payoutN = 1e18 - payoutP;
```

The oracle value should be documented as the ETH price in USDC terms, scaled by
`1e18`.

## Error Handling

Keep the existing safety checks:

- `ZeroStrike`, `StrikeTooLarge`, `ZeroMaturity`, and `ZeroOracle`.
- `ZeroAmount` and `AmountTooLarge`.
- Lifecycle guards for split, combine, settle, and redeem.
- `InvalidRecipient` before any burn path.
- `EthTransferFailed`.
- Unresolved and zero oracle value checks.

Do not add pair-validation errors. The ETH/USDC pair is no longer an input.

## Testing

Update tests to prove the narrower product surface:

- Construct `OptionSeries` with only `strike`, `maturity`, and `oracle`.
- Call `OptionFactory.createSeries` with only `strike`, `maturity`, and
  `oracle`.
- Decode the smaller factory event and assert the deployed P/N token addresses.
- Assert fixed P/N token names and symbols.
- Rename test fixtures and assertion labels from generic ticker/index wording to
  ETH/USDC price wording where that makes intent clearer.
- Preserve all existing behavioral tests for split/combine, settlement,
  redemption, zero receiver handling, overflow bounds, lifecycle guards, and
  fragmented redemption dust.

Verification commands:

```bash
forge fmt
forge test
git diff --check
```

## Acceptance Criteria

- `OptionSeries` no longer accepts or stores caller-provided ticker or token
  metadata.
- `OptionFactory.createSeries` accepts only `strike`, `maturity`, and `oracle`.
- Public docs and NatSpec describe the product as ETH/USDC-specific.
- Existing accounting behavior is unchanged.
- The full Foundry test suite passes.

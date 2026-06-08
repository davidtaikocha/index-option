# Index Options

ETH-collateralized ETH/USDC **P / N** option primitive, based on the idea in
[Building index-tracking assets on top of options instead of debt](https://ethresear.ch/t/building-index-tracking-assets-on-top-of-options-instead-of-debt/25036/).
The repo contains the Solidity contracts (Foundry) plus a SvelteKit web app for the
primary market, both targeting the Taiko Hoodi testnet.

- **Live app:** https://index-option-ui.vercel.app
- **Network:** Taiko Hoodi (chain id `167013`) · RPC `https://rpc.hoodi.taiko.xyz` · explorer `https://hoodi.taikoscan.io`
- **OptionFactory:** [`0x32231734d2F09fAa3b6bE8c50D716a94f5519A88`](https://hoodi.taikoscan.io/address/0x32231734d2F09fAa3b6bE8c50D716a94f5519A88)

> Research prototype. Not audited. Do not use with real funds.

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

The option contracts are UUPS-upgradeable (`OwnableUpgradeable` + `UUPSUpgradeable`); the
factory deploys an ERC1967 proxy per series.

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

UUPS-upgradeable factory that deploys `OptionSeries` proxies from a shared implementation and
emits the deployed series plus its P/N token addresses. The series implementation is
upgradeable via `setSeriesImplementation` by the owner.

### `IPriceOracle`

Small oracle interface that returns the resolved ETH/USDC price:

```solidity
function getResolvedValue(address series) external view returns (bool resolved, uint256 value);
```

The core contracts depend only on this interface. Tests use `MockPriceOracle`.

## Web app (`web/`)

A bridge-ui-styled SvelteKit dapp for the **primary market** — create a series, split ETH into
P/N, and combine P/N back to ETH. Settlement and the secondary market are out of scope.

- Stack: SvelteKit + `@wagmi/core` + `viem` + Tailwind/DaisyUI.
- Public config (factory address, RPC, chain, explorer, oracle) is committed in
  `web/src/lib/env.ts`; there is no `.env` and no Vercel env config is required.
- Series are created against a fixed oracle EOA
  (`0x5f2b097ffF3BC8fE3EB254aCCBe7E81Fe50160AA`); settlement is not wired into the UI.
- Contract ABIs are generated from the Foundry `out/` artifacts and committed, so the app
  builds without Foundry.

```bash
cd web
npm install
npm run gen:abi   # regenerate ABIs from ../out (requires `forge build` first)
npm run dev       # local dev server
npm run build     # production build (@sveltejs/adapter-vercel)
```

Deployed to Vercel: https://index-option-ui.vercel.app

## Repository layout

```
src/            Solidity contracts (OptionFactory, OptionSeries, ClaimToken, interfaces)
test/           Foundry tests, incl. UUPS upgradeability coverage
script/         Deploy.s.sol (impls + factory proxy), DeploySeries.s.sol (create a series)
web/            SvelteKit primary-market dapp
```

## Development

Install Foundry, then run:

```bash
forge test -vvv     # run the test suite
forge fmt           # format Solidity
git diff --check    # check whitespace
```

## Deployment

```bash
# Deploy OptionSeries + OptionFactory implementations and the factory proxy.
forge script script/Deploy.s.sol --rpc-url "$RPC_URL" --broadcast

# Create a new series through an existing factory proxy.
forge script script/DeploySeries.s.sol --rpc-url "$RPC_URL" --broadcast
```

`Deploy.s.sol` reads `PRIVATE_KEY` and optional `UPGRADE_ADMIN`; `DeploySeries.s.sol` also reads
`OPTION_FACTORY`, `SERIES_STRIKE`, `SERIES_MATURITY`, and `SERIES_ORACLE`. See `.env.example`.

## Test coverage

The Foundry suite covers restricted mint/burn and ERC20-like transfers, splitting and combining,
maturity and lifecycle guards, oracle settlement below/at/above strike, independent P/N redemption,
zero-receiver handling, fixed-point overflow guards, fragmented redemption dust, UUPS
upgradeability and authorization, and factory deployment/event contents.

## Status

Research prototype on testnet. Not audited. Do not use with real funds.

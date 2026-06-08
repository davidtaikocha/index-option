# UUPS Deployment Design

## Context

The current Foundry prototype has constructor-based contracts:

- `OptionFactory` is a stateless normal contract that deploys `OptionSeries`.
- `OptionSeries` uses constructor arguments and immutable storage for strike,
  maturity, oracle, and claim-token addresses.
- `ClaimToken` is a minimal ERC20-like token deployed by each `OptionSeries`.
- There is no `script/` directory, no `.env.example`, no OpenZeppelin
  dependency, and `foundry.toml` does not pin an EVM version.

The requested target is UUPS-upgradeable deployment support, including contract
conversion, deployment scripts, `.env.example`, and Shanghai EVM compatibility.

## Goals

- Convert `OptionFactory` to a UUPS-upgradeable implementation.
- Convert `OptionSeries` to a UUPS-upgradeable implementation.
- Keep `ClaimToken` non-upgradeable and deployed normally by each initialized
  series proxy.
- Add Foundry scripts for deploying the factory proxy and creating new series
  proxies.
- Add `.env.example` with deployment variables.
- Pin Foundry compilation and testing to the Shanghai EVM.
- Preserve existing split, combine, settlement, redemption, overflow, receiver,
  and dust behavior.

## Non-Goals

- Do not make every `ClaimToken` upgradeable.
- Do not add production oracle logic.
- Do not add AMM, rolling/perpetual, liquidation, funding, or wrapper logic.
- Do not add upgrade scripts in the first pass.
- Do not migrate existing deployed contracts.

## Dependencies

Add OpenZeppelin upgradeable contracts and script support:

- `openzeppelin-contracts-upgradeable` for `Initializable`,
  `OwnableUpgradeable`, and `UUPSUpgradeable`.
- `openzeppelin-contracts` for `ERC1967Proxy`.
- `forge-std` for Foundry deployment scripts and console logging.

Install these as Foundry `lib/` dependencies and add remappings for:

```text
@openzeppelin/contracts-upgradeable/=lib/openzeppelin-contracts-upgradeable/contracts/
@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/
forge-std/=lib/forge-std/src/
```

Use raw `ERC1967Proxy` deployment from Solidity scripts instead of the
OpenZeppelin Foundry Upgrades plugin. This keeps the prototype explicit and
small. Upgrade validation beyond local tests is out of scope for this pass.

## Architecture

The upgradeable boundary is:

- `OptionFactory`: deployed behind a UUPS proxy.
- `OptionSeries`: each series is deployed behind a UUPS proxy.

`ClaimToken` remains a normal contract. Each `OptionSeries` proxy creates its P
and N tokens during initialization. Those tokens keep using `series =
msg.sender` as their mint/burn authority, which means the proxy address controls
the token supply rather than the implementation address.

Both upgradeable implementations use `OwnableUpgradeable` and restrict
`_authorizeUpgrade` with `onlyOwner`. The owner is the explicit upgrade admin
address.

## OptionSeries Conversion

Replace constructor/immutable setup with initializer-based setup:

```solidity
function initialize(
    uint256 strike_,
    uint256 maturity_,
    address oracle_,
    address upgradeAdmin_
) external initializer
```

The initializer must:

- reject zero strike;
- reject strike values that can overflow settlement math;
- reject zero maturity;
- reject zero oracle;
- reject zero upgrade admin;
- initialize ownership with `upgradeAdmin_`;
- store `strike`, `maturity`, and `oracle` as normal storage variables;
- deploy fixed ETH/USDC P/N `ClaimToken`s:
  - `Protected ETH/USDC`, `pETHUSDC`;
  - `Complement ETH/USDC`, `nETHUSDC`.

The implementation constructor must disable direct initialization:

```solidity
/// @custom:oz-upgrades-unsafe-allow constructor
constructor() {
    _disableInitializers();
}
```

Existing split/combine/settle/redeem behavior should stay unchanged.

## OptionFactory Conversion

Convert `OptionFactory` into a UUPS implementation initialized as:

```solidity
function initialize(address upgradeAdmin_, address seriesImplementation_)
    external
    initializer
```

The factory stores:

```solidity
address public seriesImplementation;
```

Initialization must reject zero upgrade admin and zero series implementation.
It must initialize ownership with `upgradeAdmin_`.

`createSeries(uint256 strike, uint256 maturity, address oracle)` deploys an
`ERC1967Proxy` whose implementation is `seriesImplementation` and whose init
calldata calls:

```solidity
OptionSeries.initialize(strike, maturity, oracle, owner())
```

The factory emits the existing reduced ETH/USDC event with the series proxy
address plus P/N token addresses.

Add an owner-only setter:

```solidity
function setSeriesImplementation(address newImplementation) external onlyOwner
```

This controls the implementation used for future series. Existing series proxies
can be upgraded individually by the same upgrade admin.

## Deployment Scripts

Create `script/Deploy.s.sol`:

- read `PRIVATE_KEY`;
- read `UPGRADE_ADMIN` with a zero-address default;
- default `upgradeAdmin` to the broadcaster address when `UPGRADE_ADMIN` is
  unset or set to the zero address;
- deploy `OptionSeries` implementation;
- deploy `OptionFactory` implementation;
- deploy an `ERC1967Proxy` for `OptionFactory`;
- initialize the factory with `upgradeAdmin` and the series implementation;
- log:
  - upgrade admin;
  - series implementation;
  - factory implementation;
  - factory proxy.

Create `script/DeploySeries.s.sol`:

- read `PRIVATE_KEY`;
- read `OPTION_FACTORY`;
- read `STRIKE`;
- read `MATURITY`;
- read `ORACLE`;
- call `OptionFactory.createSeries(STRIKE, MATURITY, ORACLE)`;
- log:
  - series proxy;
  - P token;
  - N token.

No upgrade scripts are included in this pass.

## Environment Example

Add `.env.example`:

```bash
RPC_URL=
PRIVATE_KEY=
UPGRADE_ADMIN=0x0000000000000000000000000000000000000000
OPTION_FACTORY=
STRIKE=2000000000000000000000
MATURITY=
ORACLE=
ETHERSCAN_API_KEY=
```

`UPGRADE_ADMIN` may be left unset or set to the zero address for local/dev
scripts. In either case, deployment defaults it to the broadcaster address. For
shared environments, it must be set explicitly to a nonzero address.

## Foundry Configuration

Set the EVM version explicitly:

```toml
evm_version = "shanghai"
```

Keep Solidity at `0.8.24`.

## Testing

Update existing tests to deploy and initialize UUPS series proxies where they
currently instantiate `OptionSeries` directly.

Add coverage for:

- factory proxy initialization;
- factory owner and stored `seriesImplementation`;
- factory proxy deploying an initialized series proxy;
- series proxy strike, maturity, oracle, owner, and P/N metadata;
- direct initialization rejection for both factory and series implementations;
- non-owner factory upgrade rejection;
- owner factory upgrade success;
- non-owner series upgrade rejection;
- owner series upgrade success;
- owner-only `setSeriesImplementation`;
- deploy scripts compiling;
- `Deploy.s.sol` dry-running against a local Anvil-style environment;
- `DeploySeries.s.sol` dry-running against a local Anvil-style environment when
  `OPTION_FACTORY` points at an existing factory proxy.

Existing behavioral coverage must still pass:

- split/combine lifecycle;
- settlement below, at, and above strike;
- redemption;
- zero receiver before burn;
- overflow bounds;
- fragmented redemption dust handling;
- factory event payload verification.

## Verification

Run:

```bash
forge fmt
forge test
forge script script/Deploy.s.sol --rpc-url <local anvil rpc>
forge script script/DeploySeries.s.sol --rpc-url <local anvil rpc>
git diff --check
```

The script runs should be dry runs unless `--broadcast` is intentionally added.
`DeploySeries.s.sol` requires `OPTION_FACTORY` to point at an existing factory
proxy in that local environment.

## Acceptance Criteria

- `OptionFactory` and `OptionSeries` are UUPS upgradeable.
- `ClaimToken` remains non-upgradeable.
- Factory deployment uses a UUPS proxy.
- New series deployment uses UUPS proxies.
- Upgrade authorization is owner-only and uses `UPGRADE_ADMIN`.
- `.env.example` documents the required deployment variables.
- Foundry is configured for Shanghai EVM.
- Existing protocol behavior remains unchanged.
- Full tests and deploy-script dry runs pass.

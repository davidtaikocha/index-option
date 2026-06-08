# Index Options — P/N Pair Creation UI

Design spec. Date: 2026-06-08.

## Goal

A small web app that lets a connected wallet, on the Taiko Hoodi testnet, drive the
**primary market** of the deployed Index Options contracts:

1. **Create** a new option series (the P/N token pair) via the deployed `OptionFactory`.
2. **Mint** P/N claims by splitting ETH into an existing series.
3. **Combine** equal P/N claims back into ETH (undo a mint before settlement).

It deliberately does **not** include settlement, redemption, or the secondary-market AMM.
Style and color scheme follow Taiko's `bridge-ui` package.

## Background: the contracts

Deployed on Taiko Hoodi (chain id `167013`, RPC `https://rpc.hoodi.taiko.xyz`).

- `OptionFactory` proxy: `0x32231734d2F09fAa3b6bE8c50D716a94f5519A88`
  - `createSeries(uint256 strike, uint256 maturity, address oracle) -> address series`
  - emits `OptionSeriesCreated(address indexed series, uint256 strike, uint256 maturity, address oracle, address pToken, address nToken)`
- `OptionSeries` (one per market):
  - `split(address receiver) payable -> uint256 amount` — deposit ETH, mint equal P and N (1 wei → 1 P unit + 1 N unit).
  - `combine(uint256 amount, address receiver)` — burn equal P/N, return ETH (allowed until settlement).
  - `pToken()` / `nToken()` — the `ClaimToken` addresses (`pETHUSDC`, `nETHUSDC`, 18 decimals).
  - (out of scope here: `settle`, `redeemP`, `redeemN`.)
- `MockPriceOracle` (from `test/mocks`): no constructor args, public `setResolvedValue(series, value)`,
  `getResolvedValue(series)`. Compiled artifact with bytecode exists at
  `out/MockPriceOracle.sol/MockPriceOracle.json`, so it can be deployed from the browser.

Units:
- `strike` is a 1e18 fixed-point ETH/USDC price (USDC per ETH). UI takes a human decimal
  (e.g. `3000`) and sends `parseUnits(value, 18)`.
- `maturity` is a unix timestamp (seconds). UI takes a `datetime-local` value and converts.
- split/combine amounts are wei; UI takes ETH decimals and uses `parseEther`/`formatEther`.

## Chosen approach

**Single page, three stacked cards (Create → Mint → Combine) with a shared "active series" store.**
Creating a series auto-fills its address into the Mint and Combine cards. A "Load existing series"
input lets the user also act on a series they already have. This matches the natural
primary-market flow and the bridge-ui single-column card aesthetic.

Rejected alternatives:
- **Tabbed (Create / Mint / Combine):** breaks the create→mint flow; forces manual address copying.
- **Wizard/stepper:** rigid; awkward when the user just wants to mint into an existing series.

## Stack & project layout

- SvelteKit + Vite + TailwindCSS + DaisyUI, `@wagmi/core` v2 + `viem` v2 — same stack as bridge-ui.
- Reuse bridge-ui's `tailwind.config.js` color palette, `app.css` theme variables, and fonts for
  visual fidelity. Dark-mode-first.
- New `web/` directory inside this repo (the Foundry project root stays unchanged).
- Deploy via `@sveltejs/adapter-vercel`, using the local `vercel` CLI (workspace
  `davidtaikochas-projects`).

Proposed `web/` structure:

```
web/
  src/
    lib/
      wagmi.ts              # wagmi config + custom taikoHoodi chain
      contracts.ts          # typed call/read helpers (create, deployMock, split, combine, balances)
      abi/
        optionFactory.ts
        optionSeries.ts
        claimToken.ts
        mockPriceOracle.ts  # ABI + bytecode for browser deploy
      stores.ts             # account, activeSeries, tx-status stores
      format.ts             # unit conversion + address/clipboard helpers
    components/
      ConnectButton.svelte
      NetworkGuard.svelte
      CreateSeriesCard.svelte
      MintCard.svelte        # split
      CombineCard.svelte
      SeriesSummary.svelte   # series/P/N addresses, copy + explorer links
      Toast.svelte
    routes/
      +layout.svelte
      +page.svelte
    app.css
    app.html
  static/                    # fonts/icons lifted from bridge-ui
  tailwind.config.js
  svelte.config.js           # adapter-vercel
  vite.config.ts
  package.json
  .env.example               # PUBLIC_OPTION_FACTORY, PUBLIC_RPC_URL, PUBLIC_CHAIN_ID
```

## Chain & wallet

- Custom `taikoHoodi` viem chain: id `167013`, RPC `https://rpc.hoodi.taiko.xyz`, native currency ETH,
  block explorer base URL confirmed during implementation (Taikoscan Hoodi).
- Injected/MetaMask connector by default. Optional WalletConnect later if a projectId is supplied.
- `NetworkGuard` detects wrong chain and offers add/switch to Taiko Hoodi
  (`wallet_addEthereumChain` / `switchChain`). All write actions are disabled until connected and
  on the correct chain.

## Cards

### 1. Create series
- Inputs:
  - **Strike** — decimal, labelled "USDC per ETH"; sent as `parseUnits(strike, 18)`.
  - **Maturity** — `datetime-local`; converted to unix seconds; validated strictly `> now`.
  - **Oracle** — paste an address, **or** click **Deploy mock oracle**, which deploys
    `MockPriceOracle` (no args) via `deployContract` and fills the field with the new address.
- Action: `factory.createSeries(strike, maturity, oracle)`.
- On success: `waitForTransactionReceipt`, parse the `OptionSeriesCreated` log → series, pToken,
  nToken addresses. Set as the active series (populates Mint/Combine) and render `SeriesSummary`.

### 2. Mint (split)
- Target series = active series, or a pasted "Load existing series" address (reads `pToken`/`nToken`
  to validate it).
- Input: **ETH amount** → `series.split{value: parseEther(amount)}(connectedAddress)`.
- After success: read P and N `balanceOf(connectedAddress)`, display with `formatEther`.

### 3. Combine (undo)
- Input: **amount** (claim units, ETH-scale) → `series.combine(parseEther(amount), connectedAddress)`.
- Burns equal P and N, returns ETH. Refresh balances afterward.
- Disabled if the series is settled (read a `settled()` flag; combine reverts after settlement).

## Data flow

```
form input
  → validate + unit-convert (format.ts)
  → writeContract / deployContract (contracts.ts, @wagmi/core)
  → waitForTransactionReceipt
  → parse logs (createSeries) or re-read balances (split/combine)
  → update stores (activeSeries, balances, tx-status)
  → Toast (pending / success / error)
```

Reads (`balanceOf`, `pToken`/`nToken`, `settled`) use `readContract` against the baked-in factory /
series addresses. Factory address comes from `PUBLIC_OPTION_FACTORY` (default to the deployed proxy).

## Error handling

- Client-side validation: empty/zero strike, maturity not in the future, non-positive amounts,
  malformed addresses (`isAddress`). Invalid forms keep the submit button disabled.
- Network gate: writes blocked unless connected and on chain `167013`.
- Transaction failures: user-rejected and on-chain revert reasons surfaced in the toast
  (e.g. `SplitAfterMaturity`, `CombineAfterSettlement`, `ZeroAmount`).
- All addresses are copy-to-clipboard and link to the block explorer.

## Deployment

- `@sveltejs/adapter-vercel`; build with `vite build`.
- Deploy with the local `vercel` CLI to the `davidtaikochas-projects` workspace
  (preview first, then `vercel --prod` once verified).
- Public env vars: `PUBLIC_OPTION_FACTORY`, `PUBLIC_RPC_URL`, `PUBLIC_CHAIN_ID` (defaults baked in so
  the app works with zero config).

## Out of scope

- `settle`, `redeemP`, `redeemN`.
- Secondary-market AMM (the `feat/pn-amm-secondary-market` work).
- Real oracle integration, indexing/subgraph, historical series list, multi-chain.

## Open items to confirm during implementation

- Exact Taikoscan-Hoodi explorer base URL.
- Whether to reuse bridge-ui font files from its `static/` dir or the equivalent web fonts.

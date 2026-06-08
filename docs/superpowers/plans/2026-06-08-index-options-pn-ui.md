# Index Options — P/N Pair Creation UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A bridge-ui-styled SvelteKit dapp in `web/` that drives the Index Options primary market on Taiko Hoodi — create a series (P/N pair) via the deployed factory, split ETH into P/N, and combine P/N back to ETH — deployed to Vercel.

**Architecture:** Single-page app, three stacked DaisyUI cards (Create → Mint → Combine) sharing an "active series" Svelte store. All chain interaction goes through `@wagmi/core` v2 + `viem` v2 helpers in `src/lib/`. Contract ABIs and the MockPriceOracle bytecode are generated from the Foundry `out/` artifacts (single source of truth). Theme is lifted from bridge-ui's DaisyUI config.

**Tech Stack:** SvelteKit 2 + Vite 5 + TailwindCSS 3.4 + DaisyUI 4 + `@wagmi/core` 2 + `@wagmi/connectors` 4 + `viem` 2. Deploy via `@sveltejs/adapter-vercel`.

**Key facts (verified):**
- Factory proxy (Hoodi, chain `167013`): `0x32231734d2F09fAa3b6bE8c50D716a94f5519A88`
- RPC: `https://rpc.hoodi.taiko.xyz` · Explorer: `https://hoodi.taikoscan.io`
- `strike` = USDC-per-ETH as 1e18 fixed point → `parseUnits(human, 18)`
- `maturity` = unix seconds · split/combine amounts = wei via `parseEther`
- `MockPriceOracle`: no constructor args; artifact at `out/MockPriceOracle.sol/MockPriceOracle.json`

**Working directory for all `npm` commands:** `web/` (created in Task 1). Foundry root is unchanged.

---

## File Structure

```
web/
  .gitignore
  package.json
  svelte.config.js         # adapter-vercel
  vite.config.ts
  tsconfig.json
  postcss.config.js
  tailwind.config.js       # lifted bridge-ui theme
  vitest.config.ts
  scripts/genAbi.mjs        # generates src/lib/abi/* from ../out
  src/
    app.html               # fonts (Public Sans + Clash Grotesk)
    app.css
    app.d.ts
    lib/
      env.ts                # committed public Hoodi config (not secrets)
      wagmi.ts
      stores.ts
      format.ts
      format.test.ts
      contracts.ts
      abi/                  # generated: optionFactory.ts, optionSeries.ts, claimToken.ts, mockPriceOracle.ts
    components/
      ConnectButton.svelte
      NetworkGuard.svelte
      SeriesSummary.svelte
      CreateSeriesCard.svelte
      MintCard.svelte
      CombineCard.svelte
      Toast.svelte
    routes/
      +layout.svelte
      +page.svelte
```

---

## Task 1: Scaffold SvelteKit project + tooling

**Files:**
- Create: `web/package.json`, `web/svelte.config.js`, `web/vite.config.ts`, `web/vitest.config.ts`, `web/tsconfig.json`, `web/postcss.config.js`, `web/.gitignore`, `web/src/app.d.ts`

- [ ] **Step 1: Create `web/package.json`**

```json
{
  "name": "index-option-ui",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite dev",
    "build": "vite build",
    "preview": "vite preview",
    "check": "svelte-kit sync && svelte-check --tsconfig ./tsconfig.json",
    "test": "vitest run",
    "gen:abi": "node scripts/genAbi.mjs"
  },
  "devDependencies": {
    "@sveltejs/adapter-vercel": "^5.10.2",
    "@sveltejs/kit": "^2.5.21",
    "@sveltejs/vite-plugin-svelte": "^3.1.0",
    "autoprefixer": "^10.4.18",
    "daisyui": "^4.10.3",
    "postcss": "^8.4.38",
    "svelte": "^4.2.15",
    "svelte-check": "^3.7.1",
    "tailwindcss": "^3.4.3",
    "tslib": "^2.6.2",
    "typescript": "^5.4.3",
    "vite": "^5.2.10",
    "vitest": "^1.5.3"
  },
  "dependencies": {
    "@wagmi/connectors": "^4.3.1",
    "@wagmi/core": "^2.8.1",
    "viem": "^2.9.29"
  }
}
```

- [ ] **Step 2: Create `web/svelte.config.js`**

```js
import adapter from '@sveltejs/adapter-vercel';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

/** @type {import('@sveltejs/kit').Config} */
const config = {
  preprocess: vitePreprocess(),
  kit: {
    adapter: adapter({ runtime: 'nodejs20.x' }),
    alias: { $components: 'src/components' }
  }
};

export default config;
```

- [ ] **Step 3: Create `web/vite.config.ts`**

```ts
import { sveltekit } from '@sveltejs/vite-plugin-svelte';
import { defineConfig } from 'vite';

export default defineConfig({
  plugins: [sveltekit()]
});
```

- [ ] **Step 4: Create `web/vitest.config.ts`**

```ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['src/**/*.{test,spec}.ts'],
    environment: 'node'
  }
});
```

- [ ] **Step 5: Create `web/tsconfig.json`**

```json
{
  "extends": "./.svelte-kit/tsconfig.json",
  "compilerOptions": {
    "allowJs": true,
    "checkJs": true,
    "esModuleInterop": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "skipLibCheck": true,
    "sourceMap": true,
    "strict": true,
    "moduleResolution": "bundler"
  }
}
```

- [ ] **Step 6: Create `web/postcss.config.js`**

```js
export default {
  plugins: {
    tailwindcss: {},
    autoprefixer: {}
  }
};
```

- [ ] **Step 7: Create `web/.gitignore`**

```
node_modules
/.svelte-kit
/build
.vercel
.DS_Store
```

> Public config is committed as a plain TS module (`web/src/lib/env.ts`, created in Task 4), not a `.env` file — the repo root `.gitignore` ignores `.env`, and the values (factory address, RPC, chain id, explorer) are public, so hardcoding them keeps the build zero-config on Vercel.

- [ ] **Step 8: Create `web/src/app.d.ts`**

```ts
declare global {
  namespace App {}
}

export {};
```

- [ ] **Step 9: Install dependencies**

Run: `cd web && npm install`
Expected: completes without errors; `node_modules/` created.

- [ ] **Step 10: Commit**

```bash
git add web/package.json web/package-lock.json web/svelte.config.js web/vite.config.ts web/vitest.config.ts web/tsconfig.json web/postcss.config.js web/.gitignore web/src/app.d.ts
git commit -m "chore(ui): scaffold sveltekit project"
```

---

## Task 2: Theme, fonts, base layout

**Files:**
- Create: `web/tailwind.config.js`, `web/src/app.css`, `web/src/app.html`, `web/src/routes/+layout.svelte`, `web/src/routes/+page.svelte`

- [ ] **Step 1: Create `web/tailwind.config.js`** (lifted bridge-ui dark/light DaisyUI themes)

```js
import daisyuiPlugin from 'daisyui';

/** @type {import('tailwindcss').Config} */
export default {
  darkMode: ['class', '[data-theme="dark"]'],
  content: ['./src/**/*.{html,js,svelte,ts}'],
  theme: {
    extend: {
      fontFamily: {
        sans: ['Public Sans', 'sans-serif'],
        display: ['Clash Grotesk', 'sans-serif']
      },
      colors: {
        pink: { 50: '#FFC6E9', 200: '#FF6FC8', 400: '#E81899', 500: '#C8047D' },
        grey: {
          5: '#FAFAFA', 10: '#F3F3F3', 50: '#E3E3E3', 100: '#CACBCE', 200: '#ADB1B8',
          500: '#5D636F', 600: '#444A55', 700: '#2B303B', 800: '#191E28', 900: '#0B101B'
        },
        green: { 300: '#47E0A0', 800: '#00321D' },
        red: { 300: '#F15C5D', 800: '#440000' }
      }
    }
  },
  plugins: [daisyuiPlugin],
  daisyui: {
    darkTheme: 'dark',
    base: true,
    styled: true,
    utils: true,
    logs: false,
    themes: [
      {
        dark: {
          'color-scheme': 'dark',
          '--btn-text-case': 'capitalize',
          primary: '#C8047D',
          'primary-focus': '#E81899',
          'primary-content': '#F3F3F3',
          secondary: '#E81899',
          'secondary-content': '#ADB1B8',
          neutral: '#2B303B',
          'neutral-focus': '#444A55',
          'neutral-content': '#F3F3F3',
          'base-100': '#0B101B',
          'base-200': '#191E28',
          'base-300': '#2B303B',
          'base-content': '#F3F3F3',
          success: '#00321D',
          'success-content': '#47E0A0',
          error: '#440000',
          'error-content': '#F15C5D',
          warning: '#382800',
          'warning-content': '#EBB222',
          info: '#002966',
          'info-content': '#8DC4FF'
        }
      }
    ]
  }
};
```

- [ ] **Step 2: Create `web/src/app.css`**

```css
@tailwind base;
@tailwind components;
@tailwind utilities;

html,
body {
  font-family: 'Public Sans', sans-serif;
  min-height: 100dvh;
}

.font-display {
  font-family: 'Clash Grotesk', sans-serif;
}
```

- [ ] **Step 3: Create `web/src/app.html`** (fonts loaded here)

```html
<!doctype html>
<html lang="en" data-theme="dark">
  <head>
    <meta charset="utf-8" />
    <link rel="icon" href="data:," />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link
      href="https://fonts.googleapis.com/css2?family=Public+Sans:wght@400;500;600;700&display=swap"
      rel="stylesheet"
    />
    <link
      href="https://api.fontshare.com/v2/css?f[]=clash-grotesk@400,500,600&display=swap"
      rel="stylesheet"
    />
    <title>Index Options — P/N</title>
    %sveltekit.head%
  </head>
  <body data-sveltekit-preload-data="hover">
    <div style="display: contents">%sveltekit.body%</div>
  </body>
</html>
```

- [ ] **Step 4: Create `web/src/routes/+layout.svelte`** (no chain wiring yet — placeholder; replaced in Task 7)

```svelte
<script lang="ts">
  import '../app.css';
</script>

<slot />
```

- [ ] **Step 5: Create `web/src/routes/+page.svelte`** (temporary smoke page)

```svelte
<main class="min-h-dvh bg-base-100 text-base-content flex items-center justify-center">
  <h1 class="font-display text-4xl text-primary">Index Options</h1>
</main>
```

- [ ] **Step 6: Run dev server and verify theme renders**

Run: `cd web && npm run dev`
Expected: server boots on `http://localhost:5173`; page shows pink "Index Options" on dark background. Stop the server (Ctrl-C) after confirming.

- [ ] **Step 7: Verify production build works**

Run: `cd web && npm run build`
Expected: build completes without errors.

- [ ] **Step 8: Commit**

```bash
git add web/tailwind.config.js web/src/app.css web/src/app.html web/src/routes/+layout.svelte web/src/routes/+page.svelte
git commit -m "feat(ui): bridge-ui theme, fonts, base layout"
```

---

## Task 3: Generate ABIs + mock bytecode from Foundry artifacts

**Files:**
- Create: `web/scripts/genAbi.mjs`
- Generated: `web/src/lib/abi/optionFactory.ts`, `optionSeries.ts`, `claimToken.ts`, `mockPriceOracle.ts`

- [ ] **Step 1: Create `web/scripts/genAbi.mjs`**

```js
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const out = resolve(here, '../../out');
const abiDir = resolve(here, '../src/lib/abi');
mkdirSync(abiDir, { recursive: true });

// [artifactPath, exportName, includeBytecode]
const targets = [
  ['OptionFactory.sol/OptionFactory.json', 'optionFactory', false],
  ['OptionSeries.sol/OptionSeries.json', 'optionSeries', false],
  ['ClaimToken.sol/ClaimToken.json', 'claimToken', false],
  ['MockPriceOracle.sol/MockPriceOracle.json', 'mockPriceOracle', true]
];

for (const [path, name, withBytecode] of targets) {
  const artifact = JSON.parse(readFileSync(resolve(out, path), 'utf8'));
  let body = `export const ${name}Abi = ${JSON.stringify(artifact.abi, null, 2)} as const;\n`;
  if (withBytecode) {
    body += `\nexport const ${name}Bytecode = ${JSON.stringify(artifact.bytecode.object)} as \`0x\${string}\`;\n`;
  }
  writeFileSync(resolve(abiDir, `${name}.ts`), body);
  console.log(`wrote src/lib/abi/${name}.ts`);
}
```

- [ ] **Step 2: Ensure Foundry artifacts exist, then generate**

Run: `forge build && cd web && npm run gen:abi`
Expected: prints four `wrote src/lib/abi/...` lines. (Run `forge build` from the repo root, not `web/`.)

- [ ] **Step 3: Verify generated files type-check**

Run: `cd web && npx tsc --noEmit src/lib/abi/mockPriceOracle.ts`
Expected: no output (success). Confirm `web/src/lib/abi/mockPriceOracle.ts` contains both `mockPriceOracleAbi` and `mockPriceOracleBytecode` (starts with `0x6080`).

- [ ] **Step 4: Commit (commit the generated files so Vercel builds without Foundry)**

```bash
git add web/scripts/genAbi.mjs web/src/lib/abi
git commit -m "feat(ui): generate contract abis and mock oracle bytecode"
```

---

## Task 4: Public config + wagmi config + Taiko Hoodi chain

**Files:**
- Create: `web/src/lib/env.ts`, `web/src/lib/wagmi.ts`

- [ ] **Step 1: Create `web/src/lib/env.ts`** (public Hoodi config — not secrets)

```ts
import type { Address } from 'viem';

// Public Taiko Hoodi testnet configuration. None of these are secrets; they are
// committed so the app builds and deploys with zero environment configuration.
export const OPTION_FACTORY = '0x32231734d2F09fAa3b6bE8c50D716a94f5519A88' as Address;
export const RPC_URL = 'https://rpc.hoodi.taiko.xyz';
export const CHAIN_ID = 167013;
export const EXPLORER_URL = 'https://hoodi.taikoscan.io';
```

- [ ] **Step 2: Create `web/src/lib/wagmi.ts`**

```ts
import { createConfig, http } from '@wagmi/core';
import { injected } from '@wagmi/connectors';
import { defineChain } from 'viem';
import { RPC_URL, CHAIN_ID, EXPLORER_URL } from './env';

export const taikoHoodi = defineChain({
  id: CHAIN_ID,
  name: 'Taiko Hoodi',
  nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: { default: { http: [RPC_URL] } },
  blockExplorers: { default: { name: 'Taikoscan', url: EXPLORER_URL } },
  testnet: true
});

export const config = createConfig({
  chains: [taikoHoodi],
  connectors: [injected()],
  transports: { [taikoHoodi.id]: http(RPC_URL) }
});

export const explorerUrl = EXPLORER_URL;
```

- [ ] **Step 3: Verify it type-checks**

Run: `cd web && npm run check`
Expected: `svelte-check` completes with 0 errors (warnings about unused files are acceptable at this stage).

- [ ] **Step 4: Commit**

```bash
git add web/src/lib/env.ts web/src/lib/wagmi.ts
git commit -m "feat(ui): public config, wagmi config, taiko hoodi chain"
```

---

## Task 5: Pure helpers (`format.ts`) with TDD

**Files:**
- Create: `web/src/lib/format.ts`, `web/src/lib/format.test.ts`

- [ ] **Step 1: Write the failing tests — `web/src/lib/format.test.ts`**

```ts
import { describe, it, expect } from 'vitest';
import {
  toUnixSeconds,
  isFutureUnix,
  isValidAddress,
  shortenAddress,
  formatBalance,
  isPositiveDecimal
} from './format';

describe('format helpers', () => {
  it('toUnixSeconds converts a datetime-local string to seconds', () => {
    expect(toUnixSeconds('2030-01-01T00:00:00Z')).toBe(1893456000n);
  });

  it('toUnixSeconds throws on invalid input', () => {
    expect(() => toUnixSeconds('not-a-date')).toThrow();
  });

  it('isFutureUnix compares against a fixed now', () => {
    const now = 1_000_000_000_000; // ms
    expect(isFutureUnix(1_000_000_001n, now)).toBe(true);
    expect(isFutureUnix(999_999_999n, now)).toBe(false);
  });

  it('isValidAddress accepts valid and rejects invalid', () => {
    expect(isValidAddress('0x32231734d2F09fAa3b6bE8c50D716a94f5519A88')).toBe(true);
    expect(isValidAddress('0x123')).toBe(false);
    expect(isValidAddress('')).toBe(false);
  });

  it('shortenAddress truncates the middle', () => {
    expect(shortenAddress('0x32231734d2F09fAa3b6bE8c50D716a94f5519A88')).toBe('0x3223…9A88');
  });

  it('formatBalance trims to max decimals', () => {
    expect(formatBalance(1_000_000_000_000_000_000n)).toBe('1');
    expect(formatBalance(1_234_567_890_000_000_000n, 4)).toBe('1.2345');
  });

  it('isPositiveDecimal validates numeric strings', () => {
    expect(isPositiveDecimal('3000')).toBe(true);
    expect(isPositiveDecimal('0.5')).toBe(true);
    expect(isPositiveDecimal('0')).toBe(false);
    expect(isPositiveDecimal('-1')).toBe(false);
    expect(isPositiveDecimal('abc')).toBe(false);
    expect(isPositiveDecimal('')).toBe(false);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd web && npm test`
Expected: FAIL — cannot resolve `./format`.

- [ ] **Step 3: Implement `web/src/lib/format.ts`**

```ts
import { isAddress, formatEther, type Address } from 'viem';

export function toUnixSeconds(datetimeLocal: string): bigint {
  const ms = new Date(datetimeLocal).getTime();
  if (Number.isNaN(ms)) throw new Error('Invalid date');
  return BigInt(Math.floor(ms / 1000));
}

export function isFutureUnix(unix: bigint, nowMs: number = Date.now()): boolean {
  return unix > BigInt(Math.floor(nowMs / 1000));
}

export function isValidAddress(value: string): value is Address {
  return isAddress(value);
}

export function shortenAddress(addr: string): string {
  return addr.length > 10 ? `${addr.slice(0, 6)}…${addr.slice(-4)}` : addr;
}

export function formatBalance(wei: bigint, maxDecimals = 6): string {
  const [int, frac = ''] = formatEther(wei).split('.');
  const trimmed = frac.slice(0, maxDecimals).replace(/0+$/, '');
  return trimmed ? `${int}.${trimmed}` : int;
}

export function isPositiveDecimal(value: string): boolean {
  const v = value.trim();
  if (!/^\d*\.?\d+$/.test(v)) return false;
  return Number(v) > 0;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd web && npm test`
Expected: PASS — all 7 tests green.

- [ ] **Step 5: Commit**

```bash
git add web/src/lib/format.ts web/src/lib/format.test.ts
git commit -m "feat(ui): unit-conversion and validation helpers"
```

---

## Task 6: Svelte stores

**Files:**
- Create: `web/src/lib/stores.ts`

- [ ] **Step 1: Create `web/src/lib/stores.ts`**

```ts
import { writable } from 'svelte/store';
import type { Address } from 'viem';

export type AccountState = {
  address: Address | undefined;
  chainId: number | undefined;
  isConnected: boolean;
};

export const account = writable<AccountState>({
  address: undefined,
  chainId: undefined,
  isConnected: false
});

export type SeriesInfo = { series: Address; pToken: Address; nToken: Address };
export const activeSeries = writable<SeriesInfo | null>(null);

export type ToastState = { kind: 'info' | 'success' | 'error'; message: string } | null;
export const toast = writable<ToastState>(null);

let toastTimer: ReturnType<typeof setTimeout> | undefined;
export function showToast(kind: 'info' | 'success' | 'error', message: string, ms = 7000) {
  if (toastTimer) clearTimeout(toastTimer);
  toast.set({ kind, message });
  if (ms) toastTimer = setTimeout(() => toast.set(null), ms);
}
```

- [ ] **Step 2: Verify type-check**

Run: `cd web && npm run check`
Expected: 0 errors.

- [ ] **Step 3: Commit**

```bash
git add web/src/lib/stores.ts
git commit -m "feat(ui): account, series, and toast stores"
```

---

## Task 7: Contract call helpers + layout wiring

**Files:**
- Create: `web/src/lib/contracts.ts`
- Modify: `web/src/routes/+layout.svelte`

- [ ] **Step 1: Create `web/src/lib/contracts.ts`**

```ts
import {
  writeContract,
  readContract,
  waitForTransactionReceipt,
  deployContract
} from '@wagmi/core';
import { parseEventLogs, parseUnits, parseEther, type Address } from 'viem';
import { config } from './wagmi';
import { OPTION_FACTORY } from './env';
import { optionFactoryAbi } from './abi/optionFactory';
import { optionSeriesAbi } from './abi/optionSeries';
import { claimTokenAbi } from './abi/claimToken';
import { mockPriceOracleAbi, mockPriceOracleBytecode } from './abi/mockPriceOracle';

const FACTORY = OPTION_FACTORY;

export type SeriesAddresses = { series: Address; pToken: Address; nToken: Address };

export async function deployMockOracle(): Promise<Address> {
  const hash = await deployContract(config, {
    abi: mockPriceOracleAbi,
    bytecode: mockPriceOracleBytecode
  });
  const receipt = await waitForTransactionReceipt(config, { hash });
  if (!receipt.contractAddress) throw new Error('Mock oracle deployment returned no address');
  return receipt.contractAddress;
}

export async function createSeries(
  strikeHuman: string,
  maturityUnix: bigint,
  oracle: Address
): Promise<SeriesAddresses> {
  const strike = parseUnits(strikeHuman, 18);
  const hash = await writeContract(config, {
    address: FACTORY,
    abi: optionFactoryAbi,
    functionName: 'createSeries',
    args: [strike, maturityUnix, oracle]
  });
  const receipt = await waitForTransactionReceipt(config, { hash });
  const logs = parseEventLogs({
    abi: optionFactoryAbi,
    eventName: 'OptionSeriesCreated',
    logs: receipt.logs
  });
  if (logs.length === 0) throw new Error('OptionSeriesCreated event not found in receipt');
  const args = logs[0].args as { series: Address; pToken: Address; nToken: Address };
  return { series: args.series, pToken: args.pToken, nToken: args.nToken };
}

export async function loadSeries(series: Address): Promise<SeriesAddresses & { settled: boolean }> {
  const [pToken, nToken, settled] = await Promise.all([
    readContract(config, { address: series, abi: optionSeriesAbi, functionName: 'pToken' }),
    readContract(config, { address: series, abi: optionSeriesAbi, functionName: 'nToken' }),
    readContract(config, { address: series, abi: optionSeriesAbi, functionName: 'settled' })
  ]);
  return {
    series,
    pToken: pToken as Address,
    nToken: nToken as Address,
    settled: settled as boolean
  };
}

export async function splitEth(series: Address, amountEth: string, receiver: Address): Promise<void> {
  const hash = await writeContract(config, {
    address: series,
    abi: optionSeriesAbi,
    functionName: 'split',
    args: [receiver],
    value: parseEther(amountEth)
  });
  await waitForTransactionReceipt(config, { hash });
}

export async function combineEth(series: Address, amount: string, receiver: Address): Promise<void> {
  const hash = await writeContract(config, {
    address: series,
    abi: optionSeriesAbi,
    functionName: 'combine',
    args: [parseEther(amount), receiver]
  });
  await waitForTransactionReceipt(config, { hash });
}

export async function tokenBalance(token: Address, owner: Address): Promise<bigint> {
  return (await readContract(config, {
    address: token,
    abi: claimTokenAbi,
    functionName: 'balanceOf',
    args: [owner]
  })) as bigint;
}
```

- [ ] **Step 2: Replace `web/src/routes/+layout.svelte` to sync the account store**

```svelte
<script lang="ts">
  import { onMount } from 'svelte';
  import { watchAccount, getAccount, reconnect, type GetAccountReturnType } from '@wagmi/core';
  import { config } from '$lib/wagmi';
  import { account } from '$lib/stores';
  import Toast from '$components/Toast.svelte';
  import '../app.css';

  function sync(a: GetAccountReturnType) {
    account.set({ address: a.address, chainId: a.chainId, isConnected: a.isConnected });
  }

  onMount(() => {
    reconnect(config);
    sync(getAccount(config));
    return watchAccount(config, { onChange: sync });
  });
</script>

<slot />
<Toast />
```

- [ ] **Step 3: Create a minimal `web/src/components/Toast.svelte` so the layout compiles** (full styling stays here)

```svelte
<script lang="ts">
  import { toast } from '$lib/stores';

  const styles: Record<string, string> = {
    info: 'alert-info',
    success: 'alert-success',
    error: 'alert-error'
  };
</script>

{#if $toast}
  <div class="toast toast-end z-50">
    <div class="alert {styles[$toast.kind]} max-w-md">
      <span class="break-words">{$toast.message}</span>
    </div>
  </div>
{/if}
```

- [ ] **Step 4: Verify type-check and build**

Run: `cd web && npm run check && npm run build`
Expected: 0 errors; build succeeds.

- [ ] **Step 5: Commit**

```bash
git add web/src/lib/contracts.ts web/src/routes/+layout.svelte web/src/components/Toast.svelte
git commit -m "feat(ui): contract helpers, account sync, toast"
```

---

## Task 8: ConnectButton + NetworkGuard

**Files:**
- Create: `web/src/components/ConnectButton.svelte`, `web/src/components/NetworkGuard.svelte`

- [ ] **Step 1: Create `web/src/components/ConnectButton.svelte`**

```svelte
<script lang="ts">
  import { connect, disconnect } from '@wagmi/core';
  import { injected } from '@wagmi/connectors';
  import { config } from '$lib/wagmi';
  import { account, showToast } from '$lib/stores';
  import { shortenAddress } from '$lib/format';

  async function onConnect() {
    try {
      await connect(config, { connector: injected() });
    } catch (e) {
      showToast('error', (e as Error).message);
    }
  }

  async function onDisconnect() {
    await disconnect(config);
  }
</script>

{#if $account.isConnected && $account.address}
  <button class="btn btn-secondary btn-sm" on:click={onDisconnect}>
    {shortenAddress($account.address)}
  </button>
{:else}
  <button class="btn btn-primary btn-sm" on:click={onConnect}>Connect Wallet</button>
{/if}
```

- [ ] **Step 2: Create `web/src/components/NetworkGuard.svelte`**

```svelte
<script lang="ts">
  import { switchChain } from '@wagmi/core';
  import { config, taikoHoodi } from '$lib/wagmi';
  import { account, showToast } from '$lib/stores';

  $: wrongNetwork = $account.isConnected && $account.chainId !== taikoHoodi.id;

  async function onSwitch() {
    try {
      await switchChain(config, { chainId: taikoHoodi.id });
    } catch (e) {
      showToast('error', (e as Error).message);
    }
  }
</script>

{#if wrongNetwork}
  <div class="alert alert-warning flex items-center justify-between">
    <span>Wrong network — switch to Taiko Hoodi.</span>
    <button class="btn btn-sm" on:click={onSwitch}>Switch</button>
  </div>
{/if}
```

- [ ] **Step 3: Verify type-check**

Run: `cd web && npm run check`
Expected: 0 errors.

- [ ] **Step 4: Commit**

```bash
git add web/src/components/ConnectButton.svelte web/src/components/NetworkGuard.svelte
git commit -m "feat(ui): connect button and network guard"
```

---

## Task 9: SeriesSummary component

**Files:**
- Create: `web/src/components/SeriesSummary.svelte`

- [ ] **Step 1: Create `web/src/components/SeriesSummary.svelte`**

```svelte
<script lang="ts">
  import type { SeriesInfo } from '$lib/stores';
  import { showToast } from '$lib/stores';
  import { explorerUrl } from '$lib/wagmi';
  import { shortenAddress } from '$lib/format';

  export let info: SeriesInfo;

  const rows = (): { label: string; addr: string }[] => [
    { label: 'Series', addr: info.series },
    { label: 'P token (pETHUSDC)', addr: info.pToken },
    { label: 'N token (nETHUSDC)', addr: info.nToken }
  ];

  async function copy(addr: string) {
    await navigator.clipboard.writeText(addr);
    showToast('info', 'Address copied');
  }
</script>

<div class="rounded-box bg-base-200 p-4 space-y-2">
  {#each rows() as row}
    <div class="flex items-center justify-between gap-2 text-sm">
      <span class="text-base-content/70">{row.label}</span>
      <span class="flex items-center gap-2">
        <a
          class="link link-primary font-mono"
          href={`${explorerUrl}/address/${row.addr}`}
          target="_blank"
          rel="noreferrer">{shortenAddress(row.addr)}</a
        >
        <button class="btn btn-ghost btn-xs" on:click={() => copy(row.addr)}>Copy</button>
      </span>
    </div>
  {/each}
</div>
```

- [ ] **Step 2: Verify type-check**

Run: `cd web && npm run check`
Expected: 0 errors.

- [ ] **Step 3: Commit**

```bash
git add web/src/components/SeriesSummary.svelte
git commit -m "feat(ui): series summary with explorer links and copy"
```

---

## Task 10: CreateSeriesCard

**Files:**
- Create: `web/src/components/CreateSeriesCard.svelte`

- [ ] **Step 1: Create `web/src/components/CreateSeriesCard.svelte`**

```svelte
<script lang="ts">
  import type { Address } from 'viem';
  import { account, activeSeries, showToast } from '$lib/stores';
  import { taikoHoodi } from '$lib/wagmi';
  import { createSeries, deployMockOracle } from '$lib/contracts';
  import { isPositiveDecimal, isValidAddress, toUnixSeconds, isFutureUnix } from '$lib/format';

  let strike = '';
  let maturity = '';
  let oracle = '';
  let deployingOracle = false;
  let submitting = false;

  $: onCorrectNetwork = $account.isConnected && $account.chainId === taikoHoodi.id;
  $: maturityValid = maturity !== '' && (() => {
    try {
      return isFutureUnix(toUnixSeconds(maturity));
    } catch {
      return false;
    }
  })();
  $: formValid =
    isPositiveDecimal(strike) && maturityValid && isValidAddress(oracle) && onCorrectNetwork;

  async function onDeployOracle() {
    deployingOracle = true;
    try {
      const addr = await deployMockOracle();
      oracle = addr;
      showToast('success', 'Mock oracle deployed');
    } catch (e) {
      showToast('error', (e as Error).message);
    } finally {
      deployingOracle = false;
    }
  }

  async function onSubmit() {
    submitting = true;
    try {
      const info = await createSeries(strike, toUnixSeconds(maturity), oracle as Address);
      activeSeries.set(info);
      showToast('success', 'Series created');
    } catch (e) {
      showToast('error', (e as Error).message);
    } finally {
      submitting = false;
    }
  }
</script>

<section class="card bg-base-200 shadow-xl">
  <div class="card-body gap-4">
    <h2 class="card-title font-display">1 · Create series</h2>

    <label class="form-control">
      <span class="label-text">Strike (USDC per ETH)</span>
      <input class="input input-bordered" type="text" inputmode="decimal" bind:value={strike} placeholder="3000" />
    </label>

    <label class="form-control">
      <span class="label-text">Maturity</span>
      <input class="input input-bordered" type="datetime-local" bind:value={maturity} />
      {#if maturity !== '' && !maturityValid}
        <span class="label-text-alt text-error">Must be in the future</span>
      {/if}
    </label>

    <label class="form-control">
      <span class="label-text">Oracle address</span>
      <div class="join">
        <input class="input input-bordered join-item w-full font-mono text-sm" type="text" bind:value={oracle} placeholder="0x…" />
        <button class="btn join-item" on:click={onDeployOracle} disabled={!onCorrectNetwork || deployingOracle}>
          {deployingOracle ? 'Deploying…' : 'Deploy mock'}
        </button>
      </div>
      {#if oracle !== '' && !isValidAddress(oracle)}
        <span class="label-text-alt text-error">Invalid address</span>
      {/if}
    </label>

    <button class="btn btn-primary" on:click={onSubmit} disabled={!formValid || submitting}>
      {submitting ? 'Creating…' : 'Create series'}
    </button>
    {#if !onCorrectNetwork}
      <span class="text-sm text-base-content/60">Connect to Taiko Hoodi to create a series.</span>
    {/if}
  </div>
</section>
```

- [ ] **Step 2: Verify type-check**

Run: `cd web && npm run check`
Expected: 0 errors.

- [ ] **Step 3: Commit**

```bash
git add web/src/components/CreateSeriesCard.svelte
git commit -m "feat(ui): create-series card with mock oracle deploy"
```

---

## Task 11: MintCard (split + balances)

**Files:**
- Create: `web/src/components/MintCard.svelte`

- [ ] **Step 1: Create `web/src/components/MintCard.svelte`**

```svelte
<script lang="ts">
  import type { Address } from 'viem';
  import { account, activeSeries, showToast } from '$lib/stores';
  import { taikoHoodi } from '$lib/wagmi';
  import { splitEth, loadSeries, tokenBalance } from '$lib/contracts';
  import { isPositiveDecimal, isValidAddress, formatBalance } from '$lib/format';

  let manualSeries = '';
  let amount = '';
  let submitting = false;
  let pBalance: bigint | null = null;
  let nBalance: bigint | null = null;

  $: onCorrectNetwork = $account.isConnected && $account.chainId === taikoHoodi.id;
  $: target = $activeSeries?.series ?? (isValidAddress(manualSeries) ? (manualSeries as Address) : null);
  $: canSubmit = target !== null && isPositiveDecimal(amount) && onCorrectNetwork && !submitting;

  async function refreshBalances() {
    if (!$activeSeries || !$account.address) return;
    [pBalance, nBalance] = await Promise.all([
      tokenBalance($activeSeries.pToken, $account.address),
      tokenBalance($activeSeries.nToken, $account.address)
    ]);
  }

  async function onLoad() {
    if (!isValidAddress(manualSeries)) return;
    try {
      const info = await loadSeries(manualSeries as Address);
      activeSeries.set({ series: info.series, pToken: info.pToken, nToken: info.nToken });
      await refreshBalances();
      showToast('success', 'Series loaded');
    } catch (e) {
      showToast('error', (e as Error).message);
    }
  }

  async function onSplit() {
    if (!target || !$account.address) return;
    submitting = true;
    try {
      await splitEth(target, amount, $account.address);
      showToast('success', 'Minted P + N');
      await refreshBalances();
    } catch (e) {
      showToast('error', (e as Error).message);
    } finally {
      submitting = false;
    }
  }

  $: if ($activeSeries && $account.address) refreshBalances();
</script>

<section class="card bg-base-200 shadow-xl">
  <div class="card-body gap-4">
    <h2 class="card-title font-display">2 · Mint (split ETH → P + N)</h2>

    {#if !$activeSeries}
      <label class="form-control">
        <span class="label-text">Series address</span>
        <div class="join">
          <input class="input input-bordered join-item w-full font-mono text-sm" type="text" bind:value={manualSeries} placeholder="0x… (or create one above)" />
          <button class="btn join-item" on:click={onLoad} disabled={!isValidAddress(manualSeries)}>Load</button>
        </div>
      </label>
    {/if}

    <label class="form-control">
      <span class="label-text">ETH amount</span>
      <input class="input input-bordered" type="text" inputmode="decimal" bind:value={amount} placeholder="0.1" />
    </label>

    <button class="btn btn-primary" on:click={onSplit} disabled={!canSubmit}>
      {submitting ? 'Minting…' : 'Mint P + N'}
    </button>

    {#if pBalance !== null && nBalance !== null}
      <div class="flex gap-4 text-sm">
        <span class="badge badge-success badge-outline">P: {formatBalance(pBalance)}</span>
        <span class="badge badge-info badge-outline">N: {formatBalance(nBalance)}</span>
      </div>
    {/if}
  </div>
</section>
```

- [ ] **Step 2: Verify type-check**

Run: `cd web && npm run check`
Expected: 0 errors.

- [ ] **Step 3: Commit**

```bash
git add web/src/components/MintCard.svelte
git commit -m "feat(ui): mint card with split and live balances"
```

---

## Task 12: CombineCard

**Files:**
- Create: `web/src/components/CombineCard.svelte`

- [ ] **Step 1: Create `web/src/components/CombineCard.svelte`**

```svelte
<script lang="ts">
  import { account, activeSeries, showToast } from '$lib/stores';
  import { taikoHoodi } from '$lib/wagmi';
  import { combineEth } from '$lib/contracts';
  import { isPositiveDecimal } from '$lib/format';

  let amount = '';
  let submitting = false;

  $: onCorrectNetwork = $account.isConnected && $account.chainId === taikoHoodi.id;
  $: canSubmit = $activeSeries !== null && isPositiveDecimal(amount) && onCorrectNetwork && !submitting;

  async function onCombine() {
    if (!$activeSeries || !$account.address) return;
    submitting = true;
    try {
      await combineEth($activeSeries.series, amount, $account.address);
      showToast('success', 'Combined P + N → ETH');
    } catch (e) {
      showToast('error', (e as Error).message);
    } finally {
      submitting = false;
    }
  }
</script>

<section class="card bg-base-200 shadow-xl">
  <div class="card-body gap-4">
    <h2 class="card-title font-display">3 · Combine (P + N → ETH)</h2>

    {#if !$activeSeries}
      <p class="text-sm text-base-content/60">Create or load a series first.</p>
    {:else}
      <label class="form-control">
        <span class="label-text">Amount to combine</span>
        <input class="input input-bordered" type="text" inputmode="decimal" bind:value={amount} placeholder="0.1" />
      </label>
      <button class="btn btn-primary" on:click={onCombine} disabled={!canSubmit}>
        {submitting ? 'Combining…' : 'Combine'}
      </button>
    {/if}
  </div>
</section>
```

- [ ] **Step 2: Verify type-check**

Run: `cd web && npm run check`
Expected: 0 errors.

- [ ] **Step 3: Commit**

```bash
git add web/src/components/CombineCard.svelte
git commit -m "feat(ui): combine card"
```

---

## Task 13: Assemble the page

**Files:**
- Modify: `web/src/routes/+page.svelte`

- [ ] **Step 1: Replace `web/src/routes/+page.svelte`**

```svelte
<script lang="ts">
  import { activeSeries } from '$lib/stores';
  import ConnectButton from '$components/ConnectButton.svelte';
  import NetworkGuard from '$components/NetworkGuard.svelte';
  import SeriesSummary from '$components/SeriesSummary.svelte';
  import CreateSeriesCard from '$components/CreateSeriesCard.svelte';
  import MintCard from '$components/MintCard.svelte';
  import CombineCard from '$components/CombineCard.svelte';
</script>

<div class="min-h-dvh bg-base-100 text-base-content">
  <header class="border-b border-base-300">
    <div class="mx-auto flex max-w-2xl items-center justify-between px-4 py-4">
      <div class="flex flex-col">
        <span class="font-display text-xl text-primary">Index Options</span>
        <span class="text-xs text-base-content/60">P/N primary market · Taiko Hoodi</span>
      </div>
      <ConnectButton />
    </div>
  </header>

  <main class="mx-auto max-w-2xl space-y-6 px-4 py-8">
    <NetworkGuard />
    <CreateSeriesCard />
    {#if $activeSeries}
      <SeriesSummary info={$activeSeries} />
    {/if}
    <MintCard />
    <CombineCard />
  </main>
</div>
```

- [ ] **Step 2: Type-check and build**

Run: `cd web && npm run check && npm run build`
Expected: 0 errors; build succeeds.

- [ ] **Step 3: Manual end-to-end verification on Taiko Hoodi**

Run: `cd web && npm run dev`, then in a browser with a wallet funded with Hoodi ETH:
1. Connect wallet → button shows the shortened address.
2. If on the wrong network, the guard appears → Switch → guard disappears.
3. In Create: strike `3000`, a future maturity, click **Deploy mock** → oracle field fills; click **Create series** → success toast, SeriesSummary shows three addresses with working explorer links.
4. In Mint: amount `0.01` → **Mint P + N** → success; P and N badges show `0.01`.
5. In Combine: amount `0.01` → **Combine** → success.

Expected: all five steps succeed; explorer links resolve on `hoodi.taikoscan.io`. Stop the dev server when done.

- [ ] **Step 4: Commit**

```bash
git add web/src/routes/+page.svelte
git commit -m "feat(ui): assemble primary-market page"
```

---

## Task 14: Deploy to Vercel

**Files:**
- Create: `web/vercel.json`

- [ ] **Step 1: Create `web/vercel.json`** (security headers, matching bridge-ui)

```json
{
  "headers": [
    {
      "source": "/(.*)",
      "headers": [
        { "key": "X-Frame-Options", "value": "DENY" },
        { "key": "Content-Security-Policy", "value": "frame-ancestors 'none';" }
      ]
    }
  ]
}
```

- [ ] **Step 2: Confirm Vercel CLI is authenticated and the workspace is reachable**

Run: `vercel whoami && vercel teams ls`
Expected: prints the logged-in user and lists teams including `davidtaikochas-projects`. If not logged in, run `vercel login` first.

- [ ] **Step 3: Link the project to the workspace (from `web/`)**

Run: `cd web && vercel link --scope davidtaikochas-projects`
Expected: interactive link; choose/create a project (e.g. `index-option-ui`). Creates `web/.vercel/` (gitignored).

- [ ] **Step 4: Preview deploy**

Run: `cd web && vercel --scope davidtaikochas-projects`
Expected: build succeeds; prints a preview URL. Open it and repeat the Task 13 Step 3 smoke flow (connect + create at minimum).

- [ ] **Step 5: Production deploy**

Run: `cd web && vercel --prod --scope davidtaikochas-projects`
Expected: prints the production URL; app loads with the dark Taiko theme and works end-to-end.

- [ ] **Step 6: Commit**

```bash
git add web/vercel.json
git commit -m "chore(ui): vercel config and deploy"
```

---

## Notes for the implementer

- **Run order:** Foundry `out/` artifacts must exist before Task 3 (`forge build` from repo root). The generated `web/src/lib/abi/*` files are committed so Vercel never needs Foundry.
- **Config:** all public config lives in `web/src/lib/env.ts` (committed). There is no `.env` file (the repo root `.gitignore` ignores `.env`) and no Vercel environment variables are required. To point at a different factory/RPC/chain, edit `env.ts`.
- **No real oracle on Hoodi:** the mock oracle only matters at settlement (out of scope). The created series is fully usable for split/combine regardless.
- **Connector:** injected/MetaMask only. WalletConnect can be added later by installing `@walletconnect/*` and adding a `walletConnect({ projectId })` connector to `web/src/lib/wagmi.ts`.
- **Branch:** do this work on a dedicated branch (e.g. `feat/pn-primary-market-ui`), not the AMM branch.
```

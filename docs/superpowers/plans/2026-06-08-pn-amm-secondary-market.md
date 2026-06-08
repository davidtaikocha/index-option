# P/N Secondary-Market AMM Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a set-aware constant-product AMM (`OptionPool` + `OptionPoolFactory`, UUPS) as a secondary market for an `OptionSeries`'s P/N tokens, relax `OptionSeries.split` to a settlement guard, add a swap + liquidity UI to the `web/` dapp, and deploy both to Taiko Hoodi + the live Vercel app.

**Architecture:** One ETH-integrated pool per series holds only `Rp`/`Rn` reserves (no idle ETH); buys `split` ETH into a set added to reserves and pay one side out, sells pair the input with reserve and `combine` back to ETH. Constant product `Rp·Rn=k` makes `price(P)+price(N)=1` automatic. New contracts mirror the existing `OptionFactory`/`OptionSeries` UUPS pattern.

**Tech Stack:** Solidity ^0.8.24 + Foundry (custom minimal `TestBase`), OpenZeppelin upgradeable + `Math`; web: SvelteKit + `@wagmi/core` + `viem`.

**Spec:** `docs/superpowers/specs/2026-06-08-pn-amm-secondary-market-design.md`

**Key facts:**
- Deployed `OptionFactory` (Hoodi, chain `167013`): `0x32231734d2F09fAa3b6bE8c50D716a94f5519A88`, owner/upgradeAdmin `0x5f2b097ffF3BC8fE3EB254aCCBe7E81Fe50160AA`.
- `ClaimToken` is standard ERC20-like (`approve`/`transfer`/`transferFrom`/`allowance`, 18 dec).
- Tests extend `test/UUPSTestBase.sol` → `test/TestBase.sol` (custom `vm`, custom asserts). `forge test` from repo root; `forge fmt` to format.
- Deploy steps require `PRIVATE_KEY` (and `RPC_URL`, `OPTION_FACTORY`) in `.env`; the key must control the factory owner to re-point `seriesImplementation`.

---

## File Structure

```
src/OptionSeries.sol            MODIFY: split guard maturity → settlement; rename error
src/OptionPool.sol              CREATE: UUPS set-aware FPMM (reserves, swap, fund, withdraw, quotes)
src/OptionPoolFactory.sol       CREATE: UUPS factory, one pool per series
script/DeployPoolFactory.s.sol  CREATE: deploy pool impl + factory proxy
script/UpgradeSeriesImpl.s.sol  CREATE: deploy new series impl + setSeriesImplementation
test/OptionSeriesSplitCombine.t.sol   MODIFY: split-window tests
test/OptionPool.t.sol           CREATE: unit tests (fund/buy/sell/withdraw/freeze/fee/quotes)
test/OptionPoolFuzz.t.sol       CREATE: fuzz property tests (k, no-profit, positivity, price, solvency)
test/OptionPoolFactory.t.sol    CREATE: factory unit + UUPS tests
test/PoolTestBase.sol           CREATE: shared pool test setup helpers
web/src/lib/env.ts              MODIFY: add POOL_FACTORY
web/scripts/genAbi.mjs          MODIFY: add OptionPool + OptionPoolFactory targets
web/src/lib/amm.ts              CREATE: pure quote/slippage/share math (mirrors on-chain)
web/src/lib/amm.test.ts         CREATE: vitest for amm.ts
web/src/lib/pool.ts             CREATE: wagmi pool helpers (discover/create/quote/swap/fund/withdraw)
web/src/components/PoolPanel.svelte   CREATE: pool discovery + Trade + Liquidity tabs
web/src/components/TradeForm.svelte   CREATE: buy/sell P/N with quote + slippage
web/src/components/LiquidityForm.svelte CREATE: fund + withdraw
web/src/routes/+page.svelte     MODIFY: mount PoolPanel under the active series
```

---

## Task 1: Relax `OptionSeries.split` to a settlement guard

**Files:**
- Modify: `src/OptionSeries.sol`
- Modify: `test/OptionSeriesSplitCombine.t.sol`

- [ ] **Step 1: Update the two split tests in `test/OptionSeriesSplitCombine.t.sol`**

Replace the `testSplitRejectedAtMaturity` function (lines 89-95) with these two:

```solidity
    function testSplitAllowedAfterMaturityBeforeSettlement() public {
        vm.warp(maturity);

        vm.prank(alice);
        series.split{value: 1 ether}(alice);

        assertEq(pToken.balanceOf(alice), 1 ether, "alice P after maturity");
        assertEq(nToken.balanceOf(alice), 1 ether, "alice N after maturity");
    }

    function testSplitRejectedAfterSettlement() public {
        oracle.setResolvedValue(address(series), 2000e18);
        vm.warp(maturity);
        series.settle();

        vm.expectRevert(OptionSeries.SplitAfterSettlement.selector);
        vm.prank(alice);
        series.split{value: 1 ether}(alice);
    }
```

- [ ] **Step 2: Run to verify they fail**

Run: `forge test --match-contract OptionSeriesSplitCombineTest`
Expected: FAIL — `SplitAfterSettlement` is not a member of `OptionSeries`, and the old guard still rejects split at maturity.

- [ ] **Step 3: Edit `src/OptionSeries.sol`**

Rename the error (find `error SplitAfterMaturity();`):

```solidity
    /// @notice Splits are only allowed before settlement.
    error SplitAfterSettlement();
```

In `split(...)`, replace the guard line `if (block.timestamp >= maturity) revert SplitAfterMaturity();` with:

```solidity
        if (settled) revert SplitAfterSettlement();
```

- [ ] **Step 4: Run the full series suite**

Run: `forge test --match-path 'test/OptionSeries*'`
Expected: PASS (the new split tests plus all existing split/combine/settlement tests).

- [ ] **Step 5: Format and run everything**

Run: `forge fmt && forge test`
Expected: all existing tests pass (the relax does not affect other suites).

- [ ] **Step 6: Commit**

```bash
git add src/OptionSeries.sol test/OptionSeriesSplitCombine.t.sol
git commit -m "feat(series): relax split from maturity to settlement guard"
```

---

## Task 2: Pool test base

**Files:**
- Create: `test/PoolTestBase.sol`

- [ ] **Step 1: Create `test/PoolTestBase.sol`**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ClaimToken} from "../src/ClaimToken.sol";
import {OptionSeries} from "../src/OptionSeries.sol";
import {OptionPool} from "../src/OptionPool.sol";
import {MockPriceOracle} from "./mocks/MockPriceOracle.sol";
import {UUPSTestBase} from "./UUPSTestBase.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @notice Shared setup for OptionPool tests: a settled-capable series plus a pool proxy.
contract PoolTestBase is UUPSTestBase {
    MockPriceOracle internal oracle;
    OptionSeries internal series;
    ClaimToken internal pToken;
    ClaimToken internal nToken;
    OptionPool internal pool;
    uint256 internal maturity;

    address internal lp = address(0x11D);
    address internal trader = address(0x7AD);

    function _deployPoolProxy(address series_) internal returns (OptionPool deployed) {
        OptionPool implementation = new OptionPool();
        bytes memory initData = abi.encodeCall(OptionPool.initialize, (series_, upgradeAdmin));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        deployed = OptionPool(payable(address(proxy)));
    }

    function _setUpSeriesAndPool() internal {
        oracle = new MockPriceOracle();
        maturity = block.timestamp + 7 days;
        series = _deploySeriesProxy(2000e18, maturity, address(oracle));
        pToken = series.pToken();
        nToken = series.nToken();
        pool = _deployPoolProxy(address(series));
        vm.deal(lp, 100 ether);
        vm.deal(trader, 100 ether);
    }
}
```

- [ ] **Step 2: Commit (compiles once `OptionPool` exists in Task 3; commit together with Task 3).**

Defer the commit; this file is committed in Task 3 Step 6.

---

## Task 3: `OptionPool` contract

**Files:**
- Create: `src/OptionPool.sol`
- Create: `test/OptionPool.t.sol`

- [ ] **Step 1: Create `test/OptionPool.t.sol`**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OptionPool} from "../src/OptionPool.sol";
import {OptionSeries} from "../src/OptionSeries.sol";
import {PoolTestBase} from "./PoolTestBase.sol";

contract OptionPoolTest is PoolTestBase {
    function setUp() public {
        _setUpSeriesAndPool();
    }

    function _fundFirst(address who, uint256 eth, uint256 priceP) internal {
        vm.prank(who);
        pool.fund{value: eth}(priceP);
    }

    function testInitializeWiresSeriesAndTokens() public view {
        assertEq(address(pool.series()), address(series), "series");
        assertEq(address(pool.pToken()), address(pToken), "pToken");
        assertEq(address(pool.nToken()), address(nToken), "nToken");
        assertEq(pool.feeBps(), 30, "default fee");
    }

    function testFirstFundSetsPriceAndReturnsExcess() public {
        // priceP = 0.5 → equal reserves, no excess returned.
        _fundFirst(lp, 10 ether, 0.5e18);
        (uint256 rp, uint256 rn) = pool.getReserves();
        assertEq(rp, 10 ether, "reserveP");
        assertEq(rn, 10 ether, "reserveN");
        assertEq(pool.totalShares(), 10 ether, "shares");
        assertEq(pool.sharesOf(lp), 10 ether, "lp shares");
        assertEq(pool.spotPriceP(), 0.5e18, "spot price");
    }

    function testFirstFundBelowHalfReturnsN() public {
        // priceP = 0.25 → reserveP=e, reserveN=e/3; return ~2/3 N.
        _fundFirst(lp, 9 ether, 0.25e18);
        (uint256 rp, uint256 rn) = pool.getReserves();
        assertEq(rp, 9 ether, "reserveP kept");
        assertEq(rn, 3 ether, "reserveN scaled"); // 9 * 0.25 / 0.75
        assertEq(nToken.balanceOf(lp), 6 ether, "N returned");
        assertEq(pool.spotPriceP(), 0.25e18, "price 0.25");
    }

    function testBuyPIncreasesPriceAndPaysOut() public {
        _fundFirst(lp, 10 ether, 0.5e18);
        uint256 pBefore = pToken.balanceOf(trader);

        vm.prank(trader);
        uint256 outP = pool.buyP{value: 1 ether}(0);

        assertEq(pToken.balanceOf(trader) - pBefore, outP, "received outP");
        assertTrue(outP > 0 && outP < 2 ether, "outP in range");
        assertTrue(pool.spotPriceP() > 0.5e18, "price up");
    }

    function testBuyRespectsMinOut() public {
        _fundFirst(lp, 10 ether, 0.5e18);
        vm.expectRevert(OptionPool.InsufficientOutput.selector);
        vm.prank(trader);
        pool.buyP{value: 1 ether}(100 ether);
    }

    function testSellPReturnsEth() public {
        _fundFirst(lp, 10 ether, 0.5e18);

        // Trader gets P by splitting, then sells 1 P back.
        vm.prank(trader);
        series.split{value: 2 ether}(trader);
        vm.prank(trader);
        pToken.approve(address(pool), 1 ether);

        uint256 ethBefore = trader.balance;
        vm.prank(trader);
        uint256 ethOut = pool.sellP(1 ether, 0);

        assertEq(trader.balance - ethBefore, ethOut, "received eth");
        assertTrue(ethOut > 0 && ethOut < 1 ether, "ethOut in range");
        assertTrue(pool.spotPriceP() < 0.5e18, "price down");
    }

    function testRoundTripDoesNotProfit() public {
        _fundFirst(lp, 100 ether, 0.5e18);
        vm.deal(trader, 0);
        vm.deal(trader, 10 ether);

        vm.prank(trader);
        uint256 outP = pool.buyP{value: 1 ether}(0);
        vm.prank(trader);
        pToken.approve(address(pool), outP);
        vm.prank(trader);
        uint256 ethBack = pool.sellP(outP, 0);

        assertLe(ethBack, 1 ether, "no profit on round trip");
    }

    function testLaterFundIsProportionalAndMintsShares() public {
        _fundFirst(lp, 10 ether, 0.5e18);

        vm.prank(trader);
        pool.fund{value: 4 ether}(0);

        // Equal reserves → 4 ETH adds 4 P + 4 N, mints 4 shares.
        (uint256 rp, uint256 rn) = pool.getReserves();
        assertEq(rp, 14 ether, "reserveP");
        assertEq(rn, 14 ether, "reserveN");
        assertEq(pool.sharesOf(trader), 4 ether, "shares minted");
    }

    function testWithdrawReturnsProRataPN() public {
        _fundFirst(lp, 10 ether, 0.5e18);

        vm.prank(lp);
        (uint256 outP, uint256 outN) = pool.withdraw(4 ether);

        assertEq(outP, 4 ether, "outP");
        assertEq(outN, 4 ether, "outN");
        assertEq(pToken.balanceOf(lp), 4 ether, "P to lp");
        assertEq(nToken.balanceOf(lp), 4 ether, "N to lp");
        assertEq(pool.totalShares(), 6 ether, "remaining shares");
    }

    function testSwapAndFundFreezeAfterSettlement() public {
        _fundFirst(lp, 10 ether, 0.5e18);
        oracle.setResolvedValue(address(series), 2000e18);
        vm.warp(maturity);
        series.settle();

        vm.expectRevert(OptionPool.PoolFrozen.selector);
        vm.prank(trader);
        pool.buyP{value: 1 ether}(0);

        vm.expectRevert(OptionPool.PoolFrozen.selector);
        vm.prank(trader);
        pool.fund{value: 1 ether}(0);

        // Withdraw still works.
        vm.prank(lp);
        pool.withdraw(1 ether);
    }

    function testFeeAccruesToReserves() public {
        _fundFirst(lp, 100 ether, 0.5e18);
        uint256 kBefore = _k();

        vm.prank(trader);
        uint256 outP = pool.buyP{value: 5 ether}(0);
        assertTrue(outP > 0, "bought");
        assertTrue(_k() > kBefore, "k grew from fee");
    }

    function testSetFeeOnlyOwnerAndCapped() public {
        vm.expectRevert();
        vm.prank(trader);
        pool.setFee(50);

        vm.prank(upgradeAdmin);
        pool.setFee(50);
        assertEq(pool.feeBps(), 50, "fee updated");

        vm.expectRevert(OptionPool.FeeTooHigh.selector);
        vm.prank(upgradeAdmin);
        pool.setFee(101);
    }

    function _k() internal view returns (uint256) {
        (uint256 rp, uint256 rn) = pool.getReserves();
        return rp * rn;
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `forge test --match-contract OptionPoolTest`
Expected: FAIL — `src/OptionPool.sol` does not exist.

- [ ] **Step 3: Create `src/OptionPool.sol`**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {OptionSeries} from "./OptionSeries.sol";
import {ClaimToken} from "./ClaimToken.sol";

/// @title OptionPool
/// @notice Set-aware constant-product AMM for one OptionSeries. Holds only P and N
///         as reserves; ETH is transient (split on buys/funds, combine on sells).
contract OptionPool is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    uint256 public constant ONE = 1e18;
    uint256 public constant BPS = 10_000;
    uint256 public constant MAX_FEE_BPS = 100;

    OptionSeries public series;
    ClaimToken public pToken;
    ClaimToken public nToken;

    uint256 public reserveP;
    uint256 public reserveN;
    uint256 public feeBps;

    uint256 public totalShares;
    mapping(address => uint256) public sharesOf;

    error ZeroAmount();
    error InvalidPrice();
    error PoolFrozen();
    error InsufficientOutput();
    error InsufficientShares();
    error FeeTooHigh();
    error EthTransferFailed();

    event Funded(address indexed funder, uint256 ethIn, uint256 addedP, uint256 addedN, uint256 shares);
    event Withdrawn(address indexed lp, uint256 shares, uint256 outP, uint256 outN);
    event Bought(address indexed buyer, bool isP, uint256 ethIn, uint256 amountOut);
    event Sold(address indexed seller, bool isP, uint256 amountIn, uint256 ethOut);
    event SharesTransfer(address indexed from, address indexed to, uint256 amount);
    event FeeSet(uint256 feeBps);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address series_, address owner_) external initializer {
        __Ownable_init(owner_);
        __ReentrancyGuard_init();
        series = OptionSeries(payable(series_));
        pToken = series.pToken();
        nToken = series.nToken();
        feeBps = 30;
    }

    receive() external payable {}

    modifier notFrozen() {
        if (series.settled()) revert PoolFrozen();
        _;
    }

    // --------------------------------------------------------------------- //
    // Liquidity
    // --------------------------------------------------------------------- //

    /// @notice Add liquidity with ETH. `priceP` (1e18) sets the start price for the
    ///         first funder and is ignored afterwards.
    function fund(uint256 priceP) external payable notFrozen nonReentrant returns (uint256 sharesMinted) {
        uint256 e = msg.value;
        if (e == 0) revert ZeroAmount();

        series.split{value: e}(address(this));

        uint256 addP;
        uint256 addN;
        if (totalShares == 0) {
            if (priceP == 0 || priceP >= ONE) revert InvalidPrice();
            if (priceP <= ONE / 2) {
                addP = e;
                addN = (e * priceP) / (ONE - priceP);
            } else {
                addN = e;
                addP = (e * (ONE - priceP)) / priceP;
            }
            sharesMinted = e;
        } else {
            if (reserveP >= reserveN) {
                addP = e;
                addN = (e * reserveN) / reserveP;
                sharesMinted = (totalShares * e) / reserveP;
            } else {
                addN = e;
                addP = (e * reserveP) / reserveN;
                sharesMinted = (totalShares * e) / reserveN;
            }
        }

        reserveP += addP;
        reserveN += addN;
        totalShares += sharesMinted;
        sharesOf[msg.sender] += sharesMinted;

        if (e > addP) pToken.transfer(msg.sender, e - addP);
        if (e > addN) nToken.transfer(msg.sender, e - addN);

        emit Funded(msg.sender, e, addP, addN, sharesMinted);
    }

    /// @notice Burn shares for pro-rata raw P and N. Always available (even settled).
    function withdraw(uint256 shareAmount) external nonReentrant returns (uint256 outP, uint256 outN) {
        if (shareAmount == 0) revert ZeroAmount();
        if (sharesOf[msg.sender] < shareAmount) revert InsufficientShares();

        outP = (reserveP * shareAmount) / totalShares;
        outN = (reserveN * shareAmount) / totalShares;

        sharesOf[msg.sender] -= shareAmount;
        totalShares -= shareAmount;
        reserveP -= outP;
        reserveN -= outN;

        pToken.transfer(msg.sender, outP);
        nToken.transfer(msg.sender, outN);

        emit Withdrawn(msg.sender, shareAmount, outP, outN);
    }

    function transferShares(address to, uint256 amount) external returns (bool) {
        if (sharesOf[msg.sender] < amount) revert InsufficientShares();
        sharesOf[msg.sender] -= amount;
        sharesOf[to] += amount;
        emit SharesTransfer(msg.sender, to, amount);
        return true;
    }

    // --------------------------------------------------------------------- //
    // Swaps
    // --------------------------------------------------------------------- //

    function buyP(uint256 minOut) external payable notFrozen nonReentrant returns (uint256 outP) {
        outP = _buy(true, minOut);
    }

    function buyN(uint256 minOut) external payable notFrozen nonReentrant returns (uint256 outN) {
        outN = _buy(false, minOut);
    }

    function sellP(uint256 inP, uint256 minEthOut) external notFrozen nonReentrant returns (uint256 ethOut) {
        ethOut = _sell(true, inP, minEthOut);
    }

    function sellN(uint256 inN, uint256 minEthOut) external notFrozen nonReentrant returns (uint256 ethOut) {
        ethOut = _sell(false, inN, minEthOut);
    }

    function _buy(bool isP, uint256 minOut) internal returns (uint256 outAmt) {
        uint256 e = msg.value;
        if (e == 0) revert ZeroAmount();

        (uint256 rOut, uint256 rOther) = isP ? (reserveP, reserveN) : (reserveN, reserveP);
        outAmt = _buyAmount(rOut, rOther, e);
        if (outAmt < minOut) revert InsufficientOutput();

        series.split{value: e}(address(this));

        if (isP) {
            reserveP = reserveP + e - outAmt;
            reserveN += e;
            pToken.transfer(msg.sender, outAmt);
        } else {
            reserveN = reserveN + e - outAmt;
            reserveP += e;
            nToken.transfer(msg.sender, outAmt);
        }

        emit Bought(msg.sender, isP, e, outAmt);
    }

    function _sell(bool isP, uint256 inAmt, uint256 minEthOut) internal returns (uint256 ethOut) {
        if (inAmt == 0) revert ZeroAmount();

        (uint256 rAdd, uint256 rOther) = isP ? (reserveP, reserveN) : (reserveN, reserveP);
        ethOut = _sellAmount(rAdd, rOther, inAmt);
        if (ethOut < minEthOut) revert InsufficientOutput();

        ClaimToken inToken = isP ? pToken : nToken;
        inToken.transferFrom(msg.sender, address(this), inAmt);

        if (isP) {
            reserveP = reserveP + inAmt - ethOut;
            reserveN -= ethOut;
        } else {
            reserveN = reserveN + inAmt - ethOut;
            reserveP -= ethOut;
        }

        series.combine(ethOut, msg.sender);

        emit Sold(msg.sender, isP, inAmt, ethOut);
    }

    // --------------------------------------------------------------------- //
    // Pricing (pure)
    // --------------------------------------------------------------------- //

    /// @dev outcome bought with `eth`: a = fee-discounted input added to the other side.
    function _buyAmount(uint256 rOut, uint256 rOther, uint256 eth) internal view returns (uint256) {
        uint256 a = (eth * (BPS - feeBps)) / BPS;
        uint256 ending = Math.ceilDiv(rOut * rOther, rOther + a);
        return rOut + a - ending;
    }

    /// @dev sell `inAmt` of the add side: r solves (rAdd+inEff-r)(rOther-r)=k (smaller root).
    function _sellAmount(uint256 rAdd, uint256 rOther, uint256 inAmt) internal view returns (uint256) {
        uint256 inEff = (inAmt * (BPS - feeBps)) / BPS;
        uint256 a = rAdd + inEff;
        uint256 sum = a + rOther;
        uint256 disc = sum * sum - 4 * rOther * inEff;
        return (sum - Math.sqrt(disc)) / 2;
    }

    function getReserves() external view returns (uint256, uint256) {
        return (reserveP, reserveN);
    }

    function spotPriceP() external view returns (uint256) {
        uint256 total = reserveP + reserveN;
        if (total == 0) return 0;
        return (reserveN * ONE) / total;
    }

    function quoteBuyP(uint256 eth) external view returns (uint256) {
        return _buyAmount(reserveP, reserveN, eth);
    }

    function quoteBuyN(uint256 eth) external view returns (uint256) {
        return _buyAmount(reserveN, reserveP, eth);
    }

    function quoteSellP(uint256 inP) external view returns (uint256) {
        return _sellAmount(reserveP, reserveN, inP);
    }

    function quoteSellN(uint256 inN) external view returns (uint256) {
        return _sellAmount(reserveN, reserveP, inN);
    }

    // --------------------------------------------------------------------- //
    // Admin
    // --------------------------------------------------------------------- //

    function setFee(uint256 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_FEE_BPS) revert FeeTooHigh();
        feeBps = newFeeBps;
        emit FeeSet(newFeeBps);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
```

- [ ] **Step 4: Run the unit suite**

Run: `forge test --match-contract OptionPoolTest -vvv`
Expected: PASS — all `OptionPoolTest` cases green.

- [ ] **Step 5: Format**

Run: `forge fmt`
Expected: no diff that breaks compilation.

- [ ] **Step 6: Commit (includes Task 2 `PoolTestBase`)**

```bash
git add src/OptionPool.sol test/OptionPool.t.sol test/PoolTestBase.sol
git commit -m "feat(pool): set-aware FPMM OptionPool with fund/swap/withdraw"
```

---

## Task 4: Fuzz property tests

**Files:**
- Create: `test/OptionPoolFuzz.t.sol`

- [ ] **Step 1: Create `test/OptionPoolFuzz.t.sol`**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OptionPool} from "../src/OptionPool.sol";
import {PoolTestBase} from "./PoolTestBase.sol";

/// @notice Foundry auto-fuzzes parameterized test functions. Inputs are clamped
///         manually (no vm.assume) to stay in valid ranges.
contract OptionPoolFuzzTest is PoolTestBase {
    function setUp() public {
        _setUpSeriesAndPool();
        vm.deal(lp, 1_000_000 ether);
        vm.deal(trader, 1_000_000 ether);
        vm.prank(lp);
        pool.fund{value: 1000 ether}(0.5e18);
    }

    function _k() internal view returns (uint256) {
        (uint256 rp, uint256 rn) = pool.getReserves();
        return rp * rn;
    }

    function testFuzzBuyKeepsKNonDecreasing(uint96 ethRaw, bool isP) public {
        uint256 eth = (uint256(ethRaw) % 500 ether) + 1; // 1 wei .. 500 ETH
        uint256 kBefore = _k();
        vm.prank(trader);
        if (isP) pool.buyP{value: eth}(0);
        else pool.buyN{value: eth}(0);
        assertTrue(_k() >= kBefore, "k non-decreasing on buy");
    }

    function testFuzzPriceSumIsOne(uint96 ethRaw) public {
        uint256 eth = (uint256(ethRaw) % 500 ether) + 1;
        vm.prank(trader);
        pool.buyP{value: eth}(0);
        (uint256 rp, uint256 rn) = pool.getReserves();
        uint256 priceP = pool.spotPriceP();
        uint256 priceN = (rp * 1e18) / (rp + rn);
        assertTrue(priceP + priceN <= 1e18 + 2 && priceP + priceN + 2 >= 1e18, "price(P)+price(N)=1");
    }

    function testFuzzBuySellRoundTripNoProfit(uint96 ethRaw) public {
        uint256 eth = (uint256(ethRaw) % 500 ether) + 1e15; // >= 0.001 ETH
        uint256 ethBefore = trader.balance;
        vm.prank(trader);
        uint256 outP = pool.buyP{value: eth}(0);
        vm.prank(trader);
        pToken.approve(address(pool), outP);
        vm.prank(trader);
        pool.sellP(outP, 0);
        assertLe(trader.balance, ethBefore, "round trip never profits");
    }

    function testFuzzReservesStayPositive(uint96 ethRaw, bool isP) public {
        uint256 eth = (uint256(ethRaw) % 500 ether) + 1;
        vm.prank(trader);
        if (isP) pool.buyP{value: eth}(0);
        else pool.buyN{value: eth}(0);
        (uint256 rp, uint256 rn) = pool.getReserves();
        assertTrue(rp > 0 && rn > 0, "reserves positive");
    }

    function testFuzzSingleLpReclaimsAllReserves(uint96 ethRaw, bool isP) public {
        uint256 eth = (uint256(ethRaw) % 500 ether) + 1;
        vm.prank(trader);
        if (isP) pool.buyP{value: eth}(0);
        else pool.buyN{value: eth}(0);

        // `lp` is the only funder (see setUp), so it holds every share and must be
        // able to reclaim exactly the reserves — the pool always has the tokens.
        (uint256 rp, uint256 rn) = pool.getReserves();
        vm.prank(lp);
        (uint256 outP, uint256 outN) = pool.withdraw(pool.totalShares());
        assertEq(outP, rp, "reclaims all P reserves");
        assertEq(outN, rn, "reclaims all N reserves");
    }
}
```

- [ ] **Step 2: Run the fuzz suite**

Run: `forge test --match-contract OptionPoolFuzzTest -vvv`
Expected: PASS for all fuzz tests (default 256 runs each). If any case fails, the math in Task 3 is wrong — fix `OptionPool` and re-run, do not loosen the assertions.

- [ ] **Step 3: Commit**

```bash
git add test/OptionPoolFuzz.t.sol
git commit -m "test(pool): fuzz invariants (k, price sum, no-profit, positivity, solvency)"
```

---

## Task 5: `OptionPoolFactory`

**Files:**
- Create: `src/OptionPoolFactory.sol`
- Create: `test/OptionPoolFactory.t.sol`

- [ ] **Step 1: Create `test/OptionPoolFactory.t.sol`**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OptionPool} from "../src/OptionPool.sol";
import {OptionPoolFactory} from "../src/OptionPoolFactory.sol";
import {OptionSeries} from "../src/OptionSeries.sol";
import {PoolTestBase} from "./PoolTestBase.sol";

contract OptionPoolFactoryTest is PoolTestBase {
    OptionPoolFactory internal factory;

    function setUp() public {
        _setUpSeriesAndPool(); // gives us a series; ignore the standalone pool

        OptionPool poolImpl = new OptionPool();
        OptionPoolFactory impl = new OptionPoolFactory();
        bytes memory initData = abi.encodeCall(OptionPoolFactory.initialize, (upgradeAdmin, address(poolImpl)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        factory = OptionPoolFactory(address(proxy));
    }

    function testCreatePoolDeploysAndRecords() public {
        address poolAddr = factory.createPool(address(series));
        assertEq(factory.poolOf(address(series)), poolAddr, "recorded");

        OptionPool created = OptionPool(payable(poolAddr));
        assertEq(address(created.series()), address(series), "pool series");
        assertEq(address(created.owner()), upgradeAdmin, "pool owner");
    }

    function testCreatePoolRejectsDuplicate() public {
        factory.createPool(address(series));
        vm.expectRevert(OptionPoolFactory.PoolExists.selector);
        factory.createPool(address(series));
    }

    function testSetPoolImplementationOnlyOwner() public {
        OptionPool newImpl = new OptionPool();
        vm.expectRevert();
        vm.prank(trader);
        factory.setPoolImplementation(address(newImpl));

        vm.prank(upgradeAdmin);
        factory.setPoolImplementation(address(newImpl));
        assertEq(factory.poolImplementation(), address(newImpl), "impl updated");
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `forge test --match-contract OptionPoolFactoryTest`
Expected: FAIL — `src/OptionPoolFactory.sol` does not exist.

- [ ] **Step 3: Create `src/OptionPoolFactory.sol`**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OptionPool} from "./OptionPool.sol";
import {OptionSeries} from "./OptionSeries.sol";

/// @title OptionPoolFactory
/// @notice Deploys one canonical OptionPool proxy per OptionSeries.
contract OptionPoolFactory is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    address public poolImplementation;
    mapping(address series => address pool) public poolOf;

    error ZeroUpgradeAdmin();
    error ZeroPoolImplementation();
    error ZeroSeries();
    error PoolExists();

    event PoolCreated(address indexed series, address pool, address pToken, address nToken);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address upgradeAdmin_, address poolImplementation_) external initializer {
        if (upgradeAdmin_ == address(0)) revert ZeroUpgradeAdmin();
        if (poolImplementation_ == address(0)) revert ZeroPoolImplementation();
        __Ownable_init(upgradeAdmin_);
        poolImplementation = poolImplementation_;
    }

    function createPool(address series) external returns (address pool) {
        if (series == address(0)) revert ZeroSeries();
        if (poolOf[series] != address(0)) revert PoolExists();

        bytes memory initData = abi.encodeCall(OptionPool.initialize, (series, owner()));
        ERC1967Proxy proxy = new ERC1967Proxy(poolImplementation, initData);
        pool = address(proxy);
        poolOf[series] = pool;

        OptionSeries s = OptionSeries(payable(series));
        emit PoolCreated(series, pool, address(s.pToken()), address(s.nToken()));
    }

    function setPoolImplementation(address newImplementation) external onlyOwner {
        if (newImplementation == address(0)) revert ZeroPoolImplementation();
        poolImplementation = newImplementation;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
```

- [ ] **Step 4: Run + format**

Run: `forge test --match-contract OptionPoolFactoryTest && forge fmt`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/OptionPoolFactory.sol test/OptionPoolFactory.t.sol
git commit -m "feat(pool): UUPS OptionPoolFactory, one pool per series"
```

---

## Task 6: UUPS upgrade tests for pool + factory

**Files:**
- Create: `test/OptionPoolUpgradeability.t.sol`

- [ ] **Step 1: Create `test/OptionPoolUpgradeability.t.sol`**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OptionPool} from "../src/OptionPool.sol";
import {OptionPoolFactory} from "../src/OptionPoolFactory.sol";
import {PoolTestBase} from "./PoolTestBase.sol";

contract OptionPoolUpgradeabilityTest is PoolTestBase {
    function setUp() public {
        _setUpSeriesAndPool();
    }

    function testPoolImplementationRejectsDirectInitialization() public {
        OptionPool impl = new OptionPool();
        vm.expectRevert();
        impl.initialize(address(series), upgradeAdmin);
    }

    function testPoolUpgradeRequiresOwner() public {
        OptionPool newImpl = new OptionPool();
        vm.expectRevert();
        vm.prank(trader);
        pool.upgradeToAndCall(address(newImpl), "");
    }

    function testPoolOwnerCanUpgrade() public {
        OptionPool newImpl = new OptionPool();
        vm.prank(upgradeAdmin);
        pool.upgradeToAndCall(address(newImpl), "");
        assertEq(_proxyImplementation(address(pool)), address(newImpl), "pool upgraded");
    }

    function testFactoryOwnerCanUpgrade() public {
        OptionPool poolImpl = new OptionPool();
        OptionPoolFactory impl = new OptionPoolFactory();
        bytes memory initData = abi.encodeCall(OptionPoolFactory.initialize, (upgradeAdmin, address(poolImpl)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        OptionPoolFactory factory = OptionPoolFactory(address(proxy));

        OptionPoolFactory newImpl = new OptionPoolFactory();
        vm.prank(upgradeAdmin);
        factory.upgradeToAndCall(address(newImpl), "");
        assertEq(_proxyImplementation(address(factory)), address(newImpl), "factory upgraded");
    }
}
```

- [ ] **Step 2: Run**

Run: `forge test --match-contract OptionPoolUpgradeabilityTest`
Expected: PASS.

- [ ] **Step 3: Run the entire suite + commit**

Run: `forge test`
Expected: every suite green (existing + new pool tests).

```bash
git add test/OptionPoolUpgradeability.t.sol
git commit -m "test(pool): UUPS upgrade authorization for pool and factory"
```

---

## Task 7: Deploy scripts

**Files:**
- Create: `script/DeployPoolFactory.s.sol`
- Create: `script/UpgradeSeriesImpl.s.sol`

- [ ] **Step 1: Create `script/DeployPoolFactory.s.sol`**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Script, console2} from "forge-std/Script.sol";
import {OptionPool} from "../src/OptionPool.sol";
import {OptionPoolFactory} from "../src/OptionPoolFactory.sol";

/// @notice Deploys the OptionPool implementation, OptionPoolFactory implementation,
///         and the UUPS pool-factory proxy.
contract DeployPoolFactory is Script {
    function run()
        external
        returns (OptionPool poolImplementation, OptionPoolFactory factoryImplementation, OptionPoolFactory factory)
    {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address upgradeAdmin = vm.envOr("UPGRADE_ADMIN", address(0));
        if (upgradeAdmin == address(0)) {
            upgradeAdmin = vm.addr(deployerPrivateKey);
        }

        vm.startBroadcast(deployerPrivateKey);
        poolImplementation = new OptionPool();
        factoryImplementation = new OptionPoolFactory();
        bytes memory initData =
            abi.encodeCall(OptionPoolFactory.initialize, (upgradeAdmin, address(poolImplementation)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(factoryImplementation), initData);
        factory = OptionPoolFactory(address(proxy));
        vm.stopBroadcast();

        console2.log("POOL_IMPLEMENTATION", address(poolImplementation));
        console2.log("POOL_FACTORY_IMPLEMENTATION", address(factoryImplementation));
        console2.log("POOL_FACTORY", address(factory));
    }
}
```

- [ ] **Step 2: Create `script/UpgradeSeriesImpl.s.sol`**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {OptionFactory} from "../src/OptionFactory.sol";
import {OptionSeries} from "../src/OptionSeries.sol";

/// @notice Deploys a new OptionSeries implementation (with the relaxed split) and
///         points the existing factory at it, so newly created series get the relax.
contract UpgradeSeriesImpl is Script {
    function run() external returns (OptionSeries newImplementation) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address factoryAddress = vm.envAddress("OPTION_FACTORY");

        vm.startBroadcast(deployerPrivateKey);
        newImplementation = new OptionSeries();
        OptionFactory(factoryAddress).setSeriesImplementation(address(newImplementation));
        vm.stopBroadcast();

        console2.log("NEW_SERIES_IMPLEMENTATION", address(newImplementation));
    }
}
```

- [ ] **Step 3: Build to confirm scripts compile**

Run: `forge build`
Expected: compiles cleanly.

- [ ] **Step 4: Commit**

```bash
git add script/DeployPoolFactory.s.sol script/UpgradeSeriesImpl.s.sol
git commit -m "feat(script): deploy pool factory and upgrade series impl"
```

---

## Task 8: Deploy to Taiko Hoodi

**Files:** none (on-chain actions). Requires `.env` with `PRIVATE_KEY` (controls the factory owner `0x5f2b…60AA`), `RPC_URL=https://rpc.hoodi.taiko.xyz`, `OPTION_FACTORY=0x32231734d2F09fAa3b6bE8c50D716a94f5519A88`, `UPGRADE_ADMIN=0x5f2b097ffF3BC8fE3EB254aCCBe7E81Fe50160AA`.

- [ ] **Step 1: Point the factory at the relaxed series implementation**

Run: `forge script script/UpgradeSeriesImpl.s.sol --rpc-url "$RPC_URL" --broadcast`
Expected: prints `NEW_SERIES_IMPLEMENTATION`; the tx succeeds (deployer is the factory owner).

- [ ] **Step 2: Deploy the pool factory**

Run: `forge script script/DeployPoolFactory.s.sol --rpc-url "$RPC_URL" --broadcast`
Expected: prints `POOL_FACTORY` (the proxy address). Record it.

- [ ] **Step 3: Record the pool factory address**

Note the `POOL_FACTORY` proxy address from Step 2 output for use in Task 9.

---

## Task 9: Web — config + ABIs

**Files:**
- Modify: `web/src/lib/env.ts`
- Modify: `web/scripts/genAbi.mjs`

- [ ] **Step 1: Add `POOL_FACTORY` to `web/src/lib/env.ts`** (use the address from Task 8 Step 2)

Add after the `SERIES_ORACLE` export:

```ts
// OptionPoolFactory proxy (secondary-market AMM).
export const POOL_FACTORY = '0x__FROM_TASK_8__' as Address;
```

> Replace `0x__FROM_TASK_8__` with the deployed `POOL_FACTORY` address. This is the one value that must come from the on-chain deploy.

- [ ] **Step 2: Add pool ABI targets in `web/scripts/genAbi.mjs`**

Replace the `targets` array with:

```js
const targets = [
  ['OptionFactory.sol/OptionFactory.json', 'optionFactory', false],
  ['OptionSeries.sol/OptionSeries.json', 'optionSeries', false],
  ['ClaimToken.sol/ClaimToken.json', 'claimToken', false],
  ['OptionPool.sol/OptionPool.json', 'optionPool', false],
  ['OptionPoolFactory.sol/OptionPoolFactory.json', 'optionPoolFactory', false]
];
```

- [ ] **Step 3: Regenerate ABIs**

Run: `forge build && cd web && npm run gen:abi`
Expected: prints five `wrote src/lib/abi/...` lines including `optionPool` and `optionPoolFactory`.

- [ ] **Step 4: Commit**

```bash
git add web/src/lib/env.ts web/scripts/genAbi.mjs web/src/lib/abi
git commit -m "feat(ui): pool factory config and generated pool ABIs"
```

---

## Task 10: Web — AMM math helpers (TDD)

**Files:**
- Create: `web/src/lib/amm.ts`
- Create: `web/src/lib/amm.test.ts`

- [ ] **Step 1: Write `web/src/lib/amm.test.ts`**

```ts
import { describe, it, expect } from 'vitest';
import { buyAmount, sellAmount, spotPriceP, applySlippage } from './amm';

const ONE = 10n ** 18n;

describe('amm math (mirrors OptionPool)', () => {
  it('buyAmount with no fee preserves k', () => {
    const rp = 10n * ONE;
    const rn = 10n * ONE;
    const e = ONE;
    const out = buyAmount(rp, rn, e, 0);
    // new reserves: rp + e - out, rn + e ; product >= rp*rn
    const k = rp * rn;
    const kNew = (rp + e - out) * (rn + e);
    expect(kNew >= k).toBe(true);
  });

  it('buyAmount returns less with a fee', () => {
    const rp = 10n * ONE;
    const rn = 10n * ONE;
    const noFee = buyAmount(rp, rn, ONE, 0);
    const withFee = buyAmount(rp, rn, ONE, 30);
    expect(withFee < noFee).toBe(true);
  });

  it('sellAmount stays below the other reserve', () => {
    const rp = 10n * ONE;
    const rn = 10n * ONE;
    const out = sellAmount(rp, rn, ONE, 30);
    expect(out > 0n && out < rn).toBe(true);
  });

  it('spotPriceP is Rn/(Rp+Rn)', () => {
    expect(spotPriceP(3n * ONE, ONE)).toBe(ONE / 4n);
  });

  it('applySlippage floors by tolerance bps', () => {
    expect(applySlippage(1000n, 50)).toBe(995n); // 0.5%
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd web && npm test`
Expected: FAIL — cannot resolve `./amm`.

- [ ] **Step 3: Create `web/src/lib/amm.ts`**

```ts
const ONE = 10n ** 18n;
const BPS = 10_000n;

function ceilDiv(a: bigint, b: bigint): bigint {
  return (a + b - 1n) / b;
}

function sqrt(value: bigint): bigint {
  if (value < 0n) throw new Error('sqrt of negative');
  if (value < 2n) return value;
  let x = value;
  let y = (x + 1n) / 2n;
  while (y < x) {
    x = y;
    y = (x + value / x) / 2n;
  }
  return x;
}

/** P (or N) out for buying with `eth`, given the bought reserve and the other reserve. */
export function buyAmount(reserveOut: bigint, reserveOther: bigint, eth: bigint, feeBps: number): bigint {
  const a = (eth * (BPS - BigInt(feeBps))) / BPS;
  const ending = ceilDiv(reserveOut * reserveOther, reserveOther + a);
  return reserveOut + a - ending;
}

/** ETH out for selling `inAmt` of the add side, given (addReserve, otherReserve). */
export function sellAmount(addReserve: bigint, otherReserve: bigint, inAmt: bigint, feeBps: number): bigint {
  const inEff = (inAmt * (BPS - BigInt(feeBps))) / BPS;
  const a = addReserve + inEff;
  const sum = a + otherReserve;
  const disc = sum * sum - 4n * otherReserve * inEff;
  return (sum - sqrt(disc)) / 2n;
}

export function spotPriceP(reserveP: bigint, reserveN: bigint): bigint {
  const total = reserveP + reserveN;
  if (total === 0n) return 0n;
  return (reserveN * ONE) / total;
}

/** Lower-bound an output by a slippage tolerance in bps (e.g. 50 = 0.5%). */
export function applySlippage(amount: bigint, toleranceBps: number): bigint {
  return (amount * (BPS - BigInt(toleranceBps))) / BPS;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd web && npm test`
Expected: PASS — amm tests plus the existing format tests.

- [ ] **Step 5: Commit**

```bash
git add web/src/lib/amm.ts web/src/lib/amm.test.ts
git commit -m "feat(ui): amm quote/slippage math mirroring OptionPool"
```

---

## Task 11: Web — pool contract helpers

**Files:**
- Create: `web/src/lib/pool.ts`

- [ ] **Step 1: Create `web/src/lib/pool.ts`**

```ts
import { writeContract, readContract, waitForTransactionReceipt } from '@wagmi/core';
import { parseEther, type Address } from 'viem';
import { config } from './wagmi';
import { POOL_FACTORY } from './env';
import { optionPoolFactoryAbi } from './abi/optionPoolFactory';
import { optionPoolAbi } from './abi/optionPool';
import { optionSeriesAbi } from './abi/optionSeries';
import { claimTokenAbi } from './abi/claimToken';

const ZERO = '0x0000000000000000000000000000000000000000';

export async function poolOf(series: Address): Promise<Address | null> {
  const addr = (await readContract(config, {
    address: POOL_FACTORY,
    abi: optionPoolFactoryAbi,
    functionName: 'poolOf',
    args: [series]
  })) as Address;
  return addr === ZERO ? null : addr;
}

export async function createPool(series: Address): Promise<Address> {
  const hash = await writeContract(config, {
    address: POOL_FACTORY,
    abi: optionPoolFactoryAbi,
    functionName: 'createPool',
    args: [series]
  });
  await waitForTransactionReceipt(config, { hash });
  const addr = await poolOf(series);
  if (!addr) throw new Error('Pool not found after creation');
  return addr;
}

export type PoolState = {
  reserveP: bigint;
  reserveN: bigint;
  priceP: bigint;
  feeBps: number;
  settled: boolean;
};

export async function readPool(pool: Address, series: Address): Promise<PoolState> {
  const [reserves, priceP, feeBps, settled] = await Promise.all([
    readContract(config, { address: pool, abi: optionPoolAbi, functionName: 'getReserves' }),
    readContract(config, { address: pool, abi: optionPoolAbi, functionName: 'spotPriceP' }),
    readContract(config, { address: pool, abi: optionPoolAbi, functionName: 'feeBps' }),
    readContract(config, { address: series, abi: optionSeriesAbi, functionName: 'settled' })
  ]);
  const [reserveP, reserveN] = reserves as [bigint, bigint];
  return {
    reserveP,
    reserveN,
    priceP: priceP as bigint,
    feeBps: Number(feeBps as bigint),
    settled: settled as boolean
  };
}

export async function sharesOf(pool: Address, owner: Address): Promise<bigint> {
  return (await readContract(config, {
    address: pool,
    abi: optionPoolAbi,
    functionName: 'sharesOf',
    args: [owner]
  })) as bigint;
}

export async function allowanceOf(token: Address, owner: Address, spender: Address): Promise<bigint> {
  return (await readContract(config, {
    address: token,
    abi: claimTokenAbi,
    functionName: 'allowance',
    args: [owner, spender]
  })) as bigint;
}

export async function approveMax(token: Address, spender: Address): Promise<void> {
  const hash = await writeContract(config, {
    address: token,
    abi: claimTokenAbi,
    functionName: 'approve',
    args: [spender, (1n << 256n) - 1n]
  });
  await waitForTransactionReceipt(config, { hash });
}

type Side = 'P' | 'N';

export async function buy(pool: Address, side: Side, ethAmount: string, minOut: bigint): Promise<void> {
  const hash = await writeContract(config, {
    address: pool,
    abi: optionPoolAbi,
    functionName: side === 'P' ? 'buyP' : 'buyN',
    args: [minOut],
    value: parseEther(ethAmount)
  });
  await waitForTransactionReceipt(config, { hash });
}

export async function sell(pool: Address, side: Side, tokenAmount: string, minEthOut: bigint): Promise<void> {
  const hash = await writeContract(config, {
    address: pool,
    abi: optionPoolAbi,
    functionName: side === 'P' ? 'sellP' : 'sellN',
    args: [parseEther(tokenAmount), minEthOut]
  });
  await waitForTransactionReceipt(config, { hash });
}

export async function fund(pool: Address, ethAmount: string, pricePHint: bigint): Promise<void> {
  const hash = await writeContract(config, {
    address: pool,
    abi: optionPoolAbi,
    functionName: 'fund',
    args: [pricePHint],
    value: parseEther(ethAmount)
  });
  await waitForTransactionReceipt(config, { hash });
}

export async function withdraw(pool: Address, shareAmount: bigint): Promise<void> {
  const hash = await writeContract(config, {
    address: pool,
    abi: optionPoolAbi,
    functionName: 'withdraw',
    args: [shareAmount]
  });
  await waitForTransactionReceipt(config, { hash });
}
```

- [ ] **Step 2: Type-check**

Run: `cd web && npm run check`
Expected: 0 errors.

- [ ] **Step 3: Commit**

```bash
git add web/src/lib/pool.ts
git commit -m "feat(ui): wagmi helpers for pool discovery, swap, and liquidity"
```

---

## Task 12: Web — TradeForm component

**Files:**
- Create: `web/src/components/TradeForm.svelte`

- [ ] **Step 1: Create `web/src/components/TradeForm.svelte`**

```svelte
<script lang="ts">
  import type { Address } from 'viem';
  import { parseEther, formatEther } from 'viem';
  import { account, showToast } from '$lib/stores';
  import { buy, sell, allowanceOf, approveMax, type PoolState } from '$lib/pool';
  import { buyAmount, sellAmount, applySlippage } from '$lib/amm';
  import { isPositiveDecimal, formatBalance } from '$lib/format';

  export let pool: Address;
  export let pToken: Address;
  export let nToken: Address;
  export let state: PoolState;
  export let feeBps = 30;
  export let onDone: () => void = () => {};

  let side: 'P' | 'N' = 'P';
  let dir: 'buy' | 'sell' = 'buy';
  let amount = '';
  let toleranceBps = 50;
  let submitting = false;

  $: rOut = side === 'P' ? state.reserveP : state.reserveN;
  $: rOther = side === 'P' ? state.reserveN : state.reserveP;
  $: amt = isPositiveDecimal(amount) ? parseEther(amount) : 0n;
  $: quote =
    amt === 0n
      ? 0n
      : dir === 'buy'
        ? buyAmount(rOut, rOther, amt, feeBps)
        : sellAmount(rOut, rOther, amt, feeBps);
  $: minOut = applySlippage(quote, toleranceBps);
  $: canSubmit = amt > 0n && quote > 0n && $account.isConnected && !submitting && !state.settled;

  async function onSubmit() {
    submitting = true;
    try {
      if (dir === 'buy') {
        await buy(pool, side, amount, minOut);
        showToast('success', `Bought ${side}`);
      } else {
        const token = side === 'P' ? pToken : nToken;
        const current = await allowanceOf(token, $account.address as Address, pool);
        if (current < amt) await approveMax(token, pool);
        await sell(pool, side, amount, minOut);
        showToast('success', `Sold ${side}`);
      }
      amount = '';
      onDone();
    } catch (e) {
      showToast('error', (e as Error).message);
    } finally {
      submitting = false;
    }
  }
</script>

<div class="space-y-4">
  <div class="flex gap-2">
    <button class="btn-soft flex-1 py-2 text-sm {side === 'P' ? '!border-pink-400 !text-grey-10' : ''}" on:click={() => (side = 'P')}>P</button>
    <button class="btn-soft flex-1 py-2 text-sm {side === 'N' ? '!border-pink-400 !text-grey-10' : ''}" on:click={() => (side = 'N')}>N</button>
    <button class="btn-soft flex-1 py-2 text-sm {dir === 'buy' ? '!border-pink-400 !text-grey-10' : ''}" on:click={() => (dir = 'buy')}>Buy</button>
    <button class="btn-soft flex-1 py-2 text-sm {dir === 'sell' ? '!border-pink-400 !text-grey-10' : ''}" on:click={() => (dir = 'sell')}>Sell</button>
  </div>

  <div>
    <span class="mb-1.5 block text-xs font-medium uppercase tracking-wider text-grey-300">
      {dir === 'buy' ? 'ETH in' : `${side} in`}
    </span>
    <input class="input-box px-3.5 py-2.5 text-sm" type="text" inputmode="decimal" bind:value={amount} placeholder="0.1" />
  </div>

  <div class="rounded-[10px] border border-grey-700 bg-grey-900/30 px-3.5 py-2.5 text-xs text-grey-300 space-y-1">
    <div class="flex justify-between"><span>Est. {dir === 'buy' ? `${side} out` : 'ETH out'}</span><span class="font-mono text-grey-100">{formatBalance(quote)}</span></div>
    <div class="flex justify-between"><span>Min received ({(toleranceBps / 100).toFixed(2)}%)</span><span class="font-mono text-grey-100">{formatBalance(minOut)}</span></div>
    <div class="flex justify-between"><span>Spot price(P)</span><span class="font-mono text-grey-100">{formatEther(state.priceP)}</span></div>
  </div>

  <button class="btn-brand w-full py-2.5 text-sm" on:click={onSubmit} disabled={!canSubmit}>
    {submitting ? 'Submitting…' : `${dir === 'buy' ? 'Buy' : 'Sell'} ${side}`}
  </button>
  {#if state.settled}
    <p class="text-center text-xs text-grey-400">Series settled — trading is frozen.</p>
  {/if}
</div>
```

- [ ] **Step 2: Type-check + commit**

Run: `cd web && npm run check`
Expected: 0 errors.

```bash
git add web/src/components/TradeForm.svelte
git commit -m "feat(ui): trade form with live quote and slippage"
```

---

## Task 13: Web — LiquidityForm component

**Files:**
- Create: `web/src/components/LiquidityForm.svelte`

- [ ] **Step 1: Create `web/src/components/LiquidityForm.svelte`**

```svelte
<script lang="ts">
  import type { Address } from 'viem';
  import { parseEther } from 'viem';
  import { account, showToast } from '$lib/stores';
  import { fund, withdraw, sharesOf, type PoolState } from '$lib/pool';
  import { isPositiveDecimal, formatBalance } from '$lib/format';

  export let pool: Address;
  export let state: PoolState;
  export let onDone: () => void = () => {};

  let tab: 'fund' | 'withdraw' = 'fund';
  let ethAmount = '';
  let priceP = '0.5';
  let shareAmount = '';
  let myShares: bigint | null = null;
  let submitting = false;

  $: isFirstFunder = state.reserveP === 0n && state.reserveN === 0n;
  $: canFund = isPositiveDecimal(ethAmount) && $account.isConnected && !submitting && !state.settled;
  $: canWithdraw = isPositiveDecimal(shareAmount) && $account.isConnected && !submitting;

  async function refreshShares() {
    if (!$account.address) return;
    myShares = await sharesOf(pool, $account.address as Address);
  }
  $: if ($account.address) refreshShares();

  async function onFund() {
    submitting = true;
    try {
      const hint = isFirstFunder && isPositiveDecimal(priceP) ? parseEther(priceP) : 0n;
      await fund(pool, ethAmount, hint);
      showToast('success', 'Liquidity added');
      ethAmount = '';
      await refreshShares();
      onDone();
    } catch (e) {
      showToast('error', (e as Error).message);
    } finally {
      submitting = false;
    }
  }

  async function onWithdraw() {
    submitting = true;
    try {
      await withdraw(pool, parseEther(shareAmount));
      showToast('success', 'Withdrew P + N — combine or redeem them on the series');
      shareAmount = '';
      await refreshShares();
      onDone();
    } catch (e) {
      showToast('error', (e as Error).message);
    } finally {
      submitting = false;
    }
  }
</script>

<div class="space-y-4">
  <div class="flex gap-2">
    <button class="btn-soft flex-1 py-2 text-sm {tab === 'fund' ? '!border-pink-400 !text-grey-10' : ''}" on:click={() => (tab = 'fund')}>Fund</button>
    <button class="btn-soft flex-1 py-2 text-sm {tab === 'withdraw' ? '!border-pink-400 !text-grey-10' : ''}" on:click={() => (tab = 'withdraw')}>Withdraw</button>
  </div>

  {#if myShares !== null}
    <p class="text-xs text-grey-300">Your LP shares: <span class="font-mono text-grey-100">{formatBalance(myShares)}</span></p>
  {/if}

  {#if tab === 'fund'}
    <div>
      <span class="mb-1.5 block text-xs font-medium uppercase tracking-wider text-grey-300">ETH amount</span>
      <input class="input-box px-3.5 py-2.5 text-sm" type="text" inputmode="decimal" bind:value={ethAmount} placeholder="1.0" />
    </div>
    {#if isFirstFunder}
      <div>
        <span class="mb-1.5 block text-xs font-medium uppercase tracking-wider text-grey-300">Start price(P) · 0–1</span>
        <input class="input-box px-3.5 py-2.5 text-sm" type="text" inputmode="decimal" bind:value={priceP} placeholder="0.5" />
        <span class="mt-1.5 block text-xs text-grey-400">You're the first LP — this sets the opening price; the heavier side's excess is returned.</span>
      </div>
    {/if}
    <button class="btn-brand w-full py-2.5 text-sm" on:click={onFund} disabled={!canFund}>
      {submitting ? 'Funding…' : 'Add liquidity'}
    </button>
    {#if state.settled}
      <p class="text-center text-xs text-grey-400">Series settled — funding is frozen.</p>
    {/if}
  {:else}
    <div>
      <span class="mb-1.5 block text-xs font-medium uppercase tracking-wider text-grey-300">Shares to withdraw</span>
      <input class="input-box px-3.5 py-2.5 text-sm" type="text" inputmode="decimal" bind:value={shareAmount} placeholder="1.0" />
      <span class="mt-1.5 block text-xs text-grey-400">Returns raw P and N. Combine (or redeem after settlement) on the series to get ETH.</span>
    </div>
    <button class="btn-brand w-full py-2.5 text-sm" on:click={onWithdraw} disabled={!canWithdraw}>
      {submitting ? 'Withdrawing…' : 'Withdraw'}
    </button>
  {/if}
</div>
```

- [ ] **Step 2: Type-check + commit**

Run: `cd web && npm run check`
Expected: 0 errors.

```bash
git add web/src/components/LiquidityForm.svelte
git commit -m "feat(ui): liquidity form (fund + withdraw)"
```

---

## Task 14: Web — PoolPanel + page wiring

**Files:**
- Create: `web/src/components/PoolPanel.svelte`
- Modify: `web/src/routes/+page.svelte`

- [ ] **Step 1: Create `web/src/components/PoolPanel.svelte`**

```svelte
<script lang="ts">
  import type { Address } from 'viem';
  import { account, showToast, type SeriesInfo } from '$lib/stores';
  import { taikoHoodi } from '$lib/wagmi';
  import { poolOf, createPool, readPool, type PoolState } from '$lib/pool';
  import TradeForm from '$components/TradeForm.svelte';
  import LiquidityForm from '$components/LiquidityForm.svelte';

  export let info: SeriesInfo;

  let pool: Address | null = null;
  let state: PoolState | null = null;
  let tab: 'trade' | 'liquidity' = 'trade';
  let loading = false;
  let creating = false;

  $: onCorrectNetwork = $account.isConnected && $account.chainId === taikoHoodi.id;

  async function load() {
    loading = true;
    try {
      pool = await poolOf(info.series);
      if (pool) state = await readPool(pool, info.series);
    } catch (e) {
      showToast('error', (e as Error).message);
    } finally {
      loading = false;
    }
  }

  async function onCreate() {
    creating = true;
    try {
      pool = await createPool(info.series);
      state = await readPool(pool, info.series);
      showToast('success', 'Pool created');
    } catch (e) {
      showToast('error', (e as Error).message);
    } finally {
      creating = false;
    }
  }

  // Reload whenever the active series changes.
  let lastSeries: Address | null = null;
  $: if (info.series !== lastSeries) {
    lastSeries = info.series;
    pool = null;
    state = null;
    load();
  }

  async function refresh() {
    if (pool) state = await readPool(pool, info.series);
  }
</script>

<section class="glass-card" data-glow-border>
  <div class="p-6 lg:p-7">
    <div class="mb-5 flex items-center gap-3">
      <span class="pill flex h-7 w-7 items-center justify-center text-xs font-bold text-pink-200">⇄</span>
      <h2 class="display text-lg text-grey-10">Secondary market</h2>
    </div>

    {#if loading}
      <p class="text-sm text-grey-400">Loading pool…</p>
    {:else if !pool}
      <p class="mb-4 text-sm text-grey-300">No pool exists for this series yet.</p>
      <button class="btn-brand w-full py-2.5 text-sm" on:click={onCreate} disabled={!onCorrectNetwork || creating}>
        {creating ? 'Creating…' : 'Create pool'}
      </button>
      {#if !onCorrectNetwork}
        <p class="mt-2 text-center text-xs text-grey-400">Connect to Taiko Hoodi to create a pool.</p>
      {/if}
    {:else if state}
      <div class="mb-4 flex gap-2">
        <button class="btn-soft flex-1 py-2 text-sm {tab === 'trade' ? '!border-pink-400 !text-grey-10' : ''}" on:click={() => (tab = 'trade')}>Trade</button>
        <button class="btn-soft flex-1 py-2 text-sm {tab === 'liquidity' ? '!border-pink-400 !text-grey-10' : ''}" on:click={() => (tab = 'liquidity')}>Liquidity</button>
      </div>
      {#if tab === 'trade'}
        <TradeForm {pool} pToken={info.pToken} nToken={info.nToken} {state} feeBps={state.feeBps} onDone={refresh} />
      {:else}
        <LiquidityForm {pool} {state} onDone={refresh} />
      {/if}
    {/if}
  </div>
</section>
```

- [ ] **Step 2: Mount `PoolPanel` in `web/src/routes/+page.svelte`**

Add the import alongside the others:

```svelte
  import PoolPanel from '$components/PoolPanel.svelte';
```

Then add this block immediately after the `CombineCard` reveal block:

```svelte
      {#if $activeSeries}
        <div class="reveal" style="animation-delay: 320ms">
          <PoolPanel info={$activeSeries} />
        </div>
      {/if}
```

- [ ] **Step 3: Type-check + build**

Run: `cd web && npm run check && npm run build`
Expected: 0 errors; build succeeds.

- [ ] **Step 4: Commit**

```bash
git add web/src/components/PoolPanel.svelte web/src/routes/+page.svelte
git commit -m "feat(ui): secondary-market panel (discovery + trade + liquidity)"
```

---

## Task 15: Deploy UI + smoke test

**Files:** none (deploy).

- [ ] **Step 1: Local smoke test**

Run: `cd web && npm run dev` (background), then load the app, connect a Hoodi-funded wallet, create a series, create a pool, fund 1 ETH at price 0.5, buy 0.1 ETH of P, then withdraw. Confirm no console errors. Stop the server.

- [ ] **Step 2: Deploy to Vercel production**

Run: `cd web && vercel deploy --prod --yes --scope davidtaikochas-projects < /dev/null`
Expected: build succeeds; aliased to `https://index-option-ui.vercel.app`.

- [ ] **Step 3: Verify live**

Load `https://index-option-ui.vercel.app`, confirm the "Secondary market" card renders under an active series with no console errors.

- [ ] **Step 4: Commit (vercel.json unchanged; nothing to commit unless config changed).**

No commit needed if no files changed in this task.

---

## Notes for the implementer

- **Run order:** Tasks 1–7 are pure Solidity and can be done before any deploy. Task 8 (deploy) must precede Task 9 Step 1 (the `POOL_FACTORY` address). The generated ABIs in Task 9 are committed so Vercel builds without Foundry.
- **Fuzz failures are real bugs:** if any Task 4 fuzz test fails, the `OptionPool` math is wrong. Fix the contract, never the assertion.
- **Owner of created pools** is the factory owner (`0x5f2b…60AA` on Hoodi) — that account can `setFee` and upgrade pools.
- **Sells need approval:** `TradeForm` checks allowance and calls `approve` before `sell`; this is two transactions on first sell.
- **`readPool` reads `settled()` on the series** (the pool exposes the freeze via the series flag); the `.catch(() => false)` guards a series that somehow lacks the selector.
- **First-funder price** must be strictly between 0 and 1; the contract reverts `InvalidPrice` otherwise.

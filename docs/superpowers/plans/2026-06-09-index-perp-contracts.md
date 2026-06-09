# Index Perp (Product A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an ETH-denominated, ETH-margined, oracle-priced perpetual giving leveraged exposure to an option-basket index, with a pooled LP vault as counterparty, on top of the existing P/N option primitive.

**Architecture:** Seven contracts. `PushOracle` (live spot + series-resolve) feeds `IndexBasket` (deterministic NAV from spot). `IndexPerp` holds positions and funding/borrow accumulators, fills at the basket level, with `PerpVault` (pooled LP house) as counterparty, `FundingMath` (pure library) for accruals, and `InsuranceFund` backstopping bad debt. The P/N primitive is unchanged.

**Tech Stack:** Foundry, Solidity 0.8.24, OpenZeppelin UUPS upgradeable (`Initializable + OwnableUpgradeable + UUPSUpgradeable`), non-upgradeable `ReentrancyGuard` (mirrors existing `OptionPool`), ERC1967 proxies, custom `TestBase` (hand-rolled `Vm`, `testFuzz*` with manual clamping).

**Spec:** `docs/superpowers/specs/2026-06-09-index-perp-contracts-design.md`

---

## File structure

| File | Responsibility |
|---|---|
| `src/interfaces/ILivePriceOracle.sol` | live spot price interface |
| `src/PushOracle.sol` | keeper-pushed spot + series resolution (implements `ILivePriceOracle` + `IPriceOracle`) |
| `src/IndexBasket.sol` | option-basket legs + deterministic `levelEth(x)` / `currentLevel()` |
| `src/FundingMath.sol` | pure library: borrow + skew-funding per-second deltas |
| `src/InsuranceFund.sol` | ETH bad-debt backstop |
| `src/PerpVault.sol` | pooled ETH LP vault, reserve accounting, profit/loss settlement |
| `src/IndexPerp.sol` | position lifecycle, accumulators, open/close/addMargin/liquidate |
| `script/DeployIndexPerp.s.sol` | deploy + wire one full set |
| `test/IndexPerpTestBase.sol` | shared deploy/wire/push helpers |
| `test/PushOracle.t.sol` … `test/IndexPerpSolvency.t.sol` | unit, fuzz, solvency tests |

**Conventions to follow (verified in repo):**
- All stateful contracts: `Initializable, OwnableUpgradeable, UUPSUpgradeable`, `constructor(){ _disableInitializers(); }`, `_authorizeUpgrade(address) internal override onlyOwner {}`.
- Custom errors only. `ONE = 1e18`, `BPS = 10_000`.
- `ReentrancyGuard` from `@openzeppelin/contracts/utils/ReentrancyGuard.sol` (same as `OptionPool`).
- Tests extend `UUPSTestBase` (which extends `TestBase`); use `vm.prank` before each external call; clamp fuzz inputs with `% range + min`; assert with `assertTrue/assertEq/assertLe`.
- Run all tests: `forge test`. Run one: `forge test --match-contract <Name> -vvv`.

---

## Task 1: ILivePriceOracle + PushOracle

**Files:**
- Create: `src/interfaces/ILivePriceOracle.sol`
- Create: `src/PushOracle.sol`
- Test: `test/PushOracle.t.sol`

- [ ] **Step 1: Write the interface**

`src/interfaces/ILivePriceOracle.sol`:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ILivePriceOracle
/// @notice Live (non-resolved) ETH/USDC spot feed for perps and index marking.
interface ILivePriceOracle {
    /// @param feedId Identifier of the price feed.
    /// @return value 1e18 USDC per ETH. Zero means unset.
    /// @return updatedAt Timestamp of the last push. Consumers enforce staleness.
    function getSpotValue(bytes32 feedId) external view returns (uint256 value, uint256 updatedAt);
}
```

- [ ] **Step 2: Write the failing test**

`test/PushOracle.t.sol`:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PushOracle} from "../src/PushOracle.sol";
import {TestBase} from "./TestBase.sol";

contract PushOracleTest is TestBase {
    PushOracle internal oracle;
    address internal owner = address(0xA11AD);
    address internal keeper = address(0xCAFE);
    bytes32 internal constant FEED = bytes32("ETHUSDC");

    function setUp() public {
        PushOracle impl = new PushOracle();
        bytes memory initData = abi.encodeCall(PushOracle.initialize, (owner, keeper));
        oracle = PushOracle(address(new ERC1967Proxy(address(impl), initData)));
    }

    function testKeeperPushStoresValueAndTime() public {
        vm.warp(1000);
        vm.prank(keeper);
        oracle.pushPrice(FEED, 2500e18);
        (uint256 v, uint256 t) = oracle.getSpotValue(FEED);
        assertEq(v, 2500e18, "value");
        assertEq(t, 1000, "updatedAt");
    }

    function testNonKeeperCannotPush() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(PushOracle.Unauthorized.selector);
        oracle.pushPrice(FEED, 2500e18);
    }

    function testZeroPriceReverts() public {
        vm.prank(keeper);
        vm.expectRevert(PushOracle.ZeroPrice.selector);
        oracle.pushPrice(FEED, 0);
    }

    function testResolveSeriesImplementsIPriceOracle() public {
        address series = address(0x5E21E5);
        vm.prank(keeper);
        oracle.resolveSeries(series, 3000e18);
        (bool resolved, uint256 v) = oracle.getResolvedValue(series);
        assertTrue(resolved, "resolved");
        assertEq(v, 3000e18, "resolved value");
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `forge test --match-contract PushOracleTest`
Expected: FAIL — `PushOracle` does not exist.

- [ ] **Step 4: Write the implementation**

`src/PushOracle.sol`:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ILivePriceOracle} from "./interfaces/ILivePriceOracle.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";

/// @title PushOracle
/// @notice Keeper-pushed ETH/USDC spot feed plus per-series resolution, so it can
///         replace the EOA oracle for OptionSeries settlement too.
contract PushOracle is Initializable, OwnableUpgradeable, UUPSUpgradeable, ILivePriceOracle, IPriceOracle {
    struct Feed {
        uint256 value;
        uint256 updatedAt;
    }

    struct Resolution {
        bool resolved;
        uint256 value;
    }

    address public keeper;
    mapping(bytes32 feedId => Feed) internal feeds;
    mapping(address series => Resolution) internal resolutions;

    error Unauthorized();
    error ZeroKeeper();
    error ZeroPrice();

    event PricePushed(bytes32 indexed feedId, uint256 value, uint256 updatedAt);
    event SeriesResolved(address indexed series, uint256 value);
    event KeeperSet(address keeper);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner_, address keeper_) external initializer {
        if (owner_ == address(0)) revert Unauthorized();
        if (keeper_ == address(0)) revert ZeroKeeper();
        __Ownable_init(owner_);
        keeper = keeper_;
    }

    modifier onlyKeeper() {
        if (msg.sender != keeper && msg.sender != owner()) revert Unauthorized();
        _;
    }

    function pushPrice(bytes32 feedId, uint256 value) external onlyKeeper {
        if (value == 0) revert ZeroPrice();
        feeds[feedId] = Feed({value: value, updatedAt: block.timestamp});
        emit PricePushed(feedId, value, block.timestamp);
    }

    function getSpotValue(bytes32 feedId) external view returns (uint256 value, uint256 updatedAt) {
        Feed storage f = feeds[feedId];
        return (f.value, f.updatedAt);
    }

    function resolveSeries(address series, uint256 value) external onlyKeeper {
        if (value == 0) revert ZeroPrice();
        resolutions[series] = Resolution({resolved: true, value: value});
        emit SeriesResolved(series, value);
    }

    function getResolvedValue(address series) external view returns (bool resolved, uint256 value) {
        Resolution storage r = resolutions[series];
        return (r.resolved, r.value);
    }

    function setKeeper(address keeper_) external onlyOwner {
        if (keeper_ == address(0)) revert ZeroKeeper();
        keeper = keeper_;
        emit KeeperSet(keeper_);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `forge test --match-contract PushOracleTest`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add src/interfaces/ILivePriceOracle.sol src/PushOracle.sol test/PushOracle.t.sol
git commit -m "feat: PushOracle live spot + series resolution"
```

---

## Task 2: IndexBasket

**Files:**
- Create: `src/IndexBasket.sol`
- Test: `test/IndexBasket.t.sol`

- [ ] **Step 1: Write the failing test**

`test/IndexBasket.t.sol`:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PushOracle} from "../src/PushOracle.sol";
import {IndexBasket} from "../src/IndexBasket.sol";
import {TestBase} from "./TestBase.sol";

contract IndexBasketTest is TestBase {
    PushOracle internal oracle;
    IndexBasket internal basket;
    address internal owner = address(0xA11AD);
    address internal keeper = address(0xCAFE);
    bytes32 internal constant FEED = bytes32("ETHUSDC");

    function _deployOracle() internal {
        PushOracle impl = new PushOracle();
        oracle = PushOracle(address(new ERC1967Proxy(address(impl), abi.encodeCall(PushOracle.initialize, (owner, keeper)))));
    }

    // single CALL leg @ K=2000, weight 1e18 -> level = max(0, 1 - 2000/x)
    function _deployBasket() internal {
        IndexBasket.IndexLeg[] memory legs = new IndexBasket.IndexLeg[](1);
        legs[0] = IndexBasket.IndexLeg({kind: IndexBasket.LegKind.CALL, strike: 2000e18, weight: 1e18});
        IndexBasket impl = new IndexBasket();
        bytes memory initData = abi.encodeCall(
            IndexBasket.initialize, (owner, address(oracle), FEED, 1 hours, 2100e18, 10000e18, legs)
        );
        basket = IndexBasket(address(new ERC1967Proxy(address(impl), initData)));
    }

    function setUp() public {
        _deployOracle();
        _deployBasket();
    }

    function testLevelMatchesCallFormula() public {
        // x=4000 -> 1 - 2000/4000 = 0.5e18
        assertEq(basket.levelEth(4000e18), 0.5e18, "call level at 4000");
        // x=2500 -> 1 - 2000/2500 = 0.2e18
        assertEq(basket.levelEth(2500e18), 0.2e18, "call level at 2500");
    }

    function testCallBelowStrikeIsZeroLevelReverts() public {
        // x=2000 -> payoff 0 -> level 0 -> NonPositiveLevel
        vm.expectRevert(IndexBasket.NonPositiveLevel.selector);
        basket.levelEth(2000e18);
    }

    function testCurrentLevelReadsFreshSpot() public {
        vm.warp(1000);
        vm.prank(keeper);
        oracle.pushPrice(FEED, 4000e18);
        assertEq(basket.currentLevel(), 0.5e18, "current level");
    }

    function testCurrentLevelRevertsWhenStale() public {
        vm.warp(1000);
        vm.prank(keeper);
        oracle.pushPrice(FEED, 4000e18);
        vm.warp(1000 + 1 hours + 1);
        vm.expectRevert(IndexBasket.StalePrice.selector);
        basket.currentLevel();
    }

    function testEmptyBasketReverts() public {
        IndexBasket.IndexLeg[] memory legs = new IndexBasket.IndexLeg[](0);
        IndexBasket impl = new IndexBasket();
        vm.expectRevert(IndexBasket.EmptyBasket.selector);
        new ERC1967Proxy(address(impl), abi.encodeCall(
            IndexBasket.initialize, (owner, address(oracle), FEED, 1 hours, 2100e18, 10000e18, legs)
        ));
    }
}
```

Note: a reverting constructor inside `new ERC1967Proxy(...)` bubbles the inner revert, so `expectRevert(EmptyBasket.selector)` matches.

- [ ] **Step 2: Run test to verify it fails**

Run: `forge test --match-contract IndexBasketTest`
Expected: FAIL — `IndexBasket` does not exist.

- [ ] **Step 3: Write the implementation**

`src/IndexBasket.sol`:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ILivePriceOracle} from "./interfaces/ILivePriceOracle.sol";

/// @title IndexBasket
/// @notice Deterministic ETH-denominated option-basket index. `levelEth(x)` is the
///         settle-at-spot value of a weighted P/N/ETH leg basket, computed purely
///         from an oracle price so it cannot be manipulated by the thin P/N pool.
contract IndexBasket is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    uint256 public constant ONE = 1e18;
    uint256 public constant MAX_LEGS = 16;
    uint256 public constant MAX_AGE_CEILING = 1 days;
    uint256 internal constant VALIDATION_STEPS = 64;

    enum LegKind {
        CAPPED, // P: min(1, K/x)
        CALL, //   N: max(0, 1 - K/x)
        ETH_SPOT //  1
    }

    struct IndexLeg {
        LegKind kind;
        uint256 strike; // 1e18; ignored for ETH_SPOT
        int256 weight; //  1e18 signed
    }

    ILivePriceOracle public oracle;
    bytes32 public feedId;
    uint256 public maxAge;
    uint256 public bandLo;
    uint256 public bandHi;
    IndexLeg[] internal _legs;

    error EmptyBasket();
    error TooManyLegs();
    error BadLeg();
    error BadBand();
    error NonPositiveLevel();
    error StalePrice();
    error ZeroPrice();
    error ParamOutOfBounds();

    event LegsSet(uint256 count);
    event MaxAgeSet(uint256 maxAge);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address owner_,
        address oracle_,
        bytes32 feedId_,
        uint256 maxAge_,
        uint256 bandLo_,
        uint256 bandHi_,
        IndexLeg[] calldata legs_
    ) external initializer {
        __Ownable_init(owner_);
        oracle = ILivePriceOracle(oracle_);
        feedId = feedId_;
        if (maxAge_ == 0 || maxAge_ > MAX_AGE_CEILING) revert ParamOutOfBounds();
        maxAge = maxAge_;
        if (bandLo_ == 0 || bandHi_ <= bandLo_) revert BadBand();
        bandLo = bandLo_;
        bandHi = bandHi_;
        _setLegs(legs_);
    }

    function legs() external view returns (IndexLeg[] memory) {
        return _legs;
    }

    function legCount() external view returns (uint256) {
        return _legs.length;
    }

    /// @notice Settle-at-spot ETH value of the basket. Reverts if non-positive.
    function levelEth(uint256 x) public view returns (uint256) {
        int256 acc;
        uint256 n = _legs.length;
        for (uint256 i; i < n; ++i) {
            IndexLeg storage leg = _legs[i];
            uint256 payoff = _ethPayoff(leg.kind, leg.strike, x);
            acc += (leg.weight * int256(payoff)) / int256(ONE);
        }
        if (acc <= 0) revert NonPositiveLevel();
        return uint256(acc);
    }

    /// @notice Level at the current fresh oracle spot.
    function currentLevel() external view returns (uint256) {
        (uint256 x, uint256 updatedAt) = oracle.getSpotValue(feedId);
        if (x == 0) revert ZeroPrice();
        if (updatedAt + maxAge < block.timestamp) revert StalePrice();
        return levelEth(x);
    }

    function setLegs(IndexLeg[] calldata legs_) external onlyOwner {
        _setLegs(legs_);
    }

    function setMaxAge(uint256 maxAge_) external onlyOwner {
        if (maxAge_ == 0 || maxAge_ > MAX_AGE_CEILING) revert ParamOutOfBounds();
        maxAge = maxAge_;
        emit MaxAgeSet(maxAge_);
    }

    function _setLegs(IndexLeg[] calldata legs_) internal {
        if (legs_.length == 0) revert EmptyBasket();
        if (legs_.length > MAX_LEGS) revert TooManyLegs();
        delete _legs;
        for (uint256 i; i < legs_.length; ++i) {
            IndexLeg calldata leg = legs_[i];
            if (leg.weight == 0) revert BadLeg();
            if (leg.kind != LegKind.ETH_SPOT && leg.strike == 0) revert BadLeg();
            _legs.push(leg);
        }
        _validateBand();
        emit LegsSet(legs_.length);
    }

    /// @dev Samples the level on a grid across [bandLo, bandHi]; reverts NonPositiveLevel
    ///      (inside levelEth) if the basket is ever non-positive in the tradeable band.
    function _validateBand() internal view {
        uint256 span = bandHi - bandLo;
        for (uint256 i; i <= VALIDATION_STEPS; ++i) {
            levelEth(bandLo + (span * i) / VALIDATION_STEPS);
        }
    }

    function _ethPayoff(LegKind kind, uint256 strike, uint256 x) internal pure returns (uint256) {
        if (kind == LegKind.ETH_SPOT) return ONE;
        if (kind == LegKind.CAPPED) return strike >= x ? ONE : (strike * ONE) / x;
        // CALL
        return strike >= x ? 0 : ONE - (strike * ONE) / x;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `forge test --match-contract IndexBasketTest`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add src/IndexBasket.sol test/IndexBasket.t.sol
git commit -m "feat: IndexBasket deterministic NAV"
```

---

## Task 3: FundingMath

**Files:**
- Create: `src/FundingMath.sol`
- Test: `test/FundingMath.t.sol`

- [ ] **Step 1: Write the failing test**

`test/FundingMath.t.sol`:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FundingMath} from "../src/FundingMath.sol";
import {TestBase} from "./TestBase.sol";

contract FundingMathHarness {
    function borrowDelta(uint256 base, uint256 reserved, uint256 assets, uint256 dt) external pure returns (uint256) {
        return FundingMath.borrowDelta(base, reserved, assets, dt);
    }

    function fundingDelta(uint256 k, uint256 longOI, uint256 shortOI, uint256 dt) external pure returns (int256) {
        return FundingMath.fundingDelta(k, longOI, shortOI, dt);
    }
}

contract FundingMathTest is TestBase {
    FundingMathHarness internal h;

    function setUp() public {
        h = new FundingMathHarness();
    }

    function testBorrowScalesWithUtilization() public {
        // base=1e6/sec, util=50% (reserved 50 of 100 assets), dt=10s
        // delta = base*util/ONE * dt = 1e6 * 0.5e18/1e18 * 10 = 5e6
        assertEq(h.borrowDelta(1e6, 50 ether, 100 ether, 10), 5e6, "half util");
        // full util
        assertEq(h.borrowDelta(1e6, 100 ether, 100 ether, 10), 1e7, "full util");
    }

    function testBorrowZeroWhenNoAssetsOrTime() public {
        assertEq(h.borrowDelta(1e6, 50 ether, 0, 10), 0, "no assets");
        assertEq(h.borrowDelta(1e6, 50 ether, 100 ether, 0), 0, "no time");
    }

    function testFundingPositiveWhenLongHeavy() public {
        // k=1e6, longOI=75, shortOI=25 -> skew=0.5e18, dt=10 -> 1e6*0.5 *10 = 5e6
        assertTrue(h.fundingDelta(1e6, 75 ether, 25 ether, 10) == 5e6, "long-heavy positive");
    }

    function testFundingNegativeWhenShortHeavy() public {
        assertTrue(h.fundingDelta(1e6, 25 ether, 75 ether, 10) == -5e6, "short-heavy negative");
    }

    function testFundingZeroWhenBalancedOrEmpty() public {
        assertTrue(h.fundingDelta(1e6, 50 ether, 50 ether, 10) == 0, "balanced");
        assertTrue(h.fundingDelta(1e6, 0, 0, 10) == 0, "empty");
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `forge test --match-contract FundingMathTest`
Expected: FAIL — `FundingMath` does not exist.

- [ ] **Step 3: Write the implementation**

`src/FundingMath.sol`:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title FundingMath
/// @notice Pure accrual math for the perpetual borrow fee and skew funding.
/// @dev All rates are per-second, scaled by 1e18. Accumulators integrate these
///      deltas over time; positions settle the delta since their entry snapshot.
library FundingMath {
    uint256 internal constant ONE = 1e18;

    /// @notice Borrow accumulator increment over `dt` seconds (>= 0).
    /// @return ETH owed per ETH of notional, scaled 1e18.
    function borrowDelta(uint256 borrowBase, uint256 reserved, uint256 vaultAssets, uint256 dt)
        internal
        pure
        returns (uint256)
    {
        if (vaultAssets == 0 || dt == 0) return 0;
        uint256 util = reserved >= vaultAssets ? ONE : (reserved * ONE) / vaultAssets;
        return ((borrowBase * util) / ONE) * dt;
    }

    /// @notice Signed funding accumulator increment over `dt` seconds.
    /// @dev Positive => longs pay shorts (open interest is long-heavy).
    function fundingDelta(uint256 fundK, uint256 longOI, uint256 shortOI, uint256 dt)
        internal
        pure
        returns (int256)
    {
        uint256 totalOI = longOI + shortOI;
        if (totalOI == 0 || dt == 0) return 0;
        int256 skew = ((int256(longOI) - int256(shortOI)) * int256(ONE)) / int256(totalOI);
        return ((int256(fundK) * skew) / int256(ONE)) * int256(dt);
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `forge test --match-contract FundingMathTest`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add src/FundingMath.sol test/FundingMath.t.sol
git commit -m "feat: FundingMath borrow + skew funding library"
```

---

## Task 4: InsuranceFund

**Files:**
- Create: `src/InsuranceFund.sol`
- Test: `test/InsuranceFund.t.sol`

- [ ] **Step 1: Write the failing test**

`test/InsuranceFund.t.sol`:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {InsuranceFund} from "../src/InsuranceFund.sol";
import {TestBase} from "./TestBase.sol";

contract InsuranceFundTest is TestBase {
    InsuranceFund internal fund;
    address internal owner = address(0xA11AD);
    address internal perp = address(0x9E97);
    address internal sink = address(0x5114);

    function setUp() public {
        InsuranceFund impl = new InsuranceFund();
        fund = InsuranceFund(payable(address(new ERC1967Proxy(address(impl), abi.encodeCall(InsuranceFund.initialize, (owner))))));
        vm.prank(owner);
        fund.setPerp(perp);
        vm.deal(address(this), 100 ether);
        fund.deposit{value: 10 ether}();
    }

    function testCoverShortfallPaysRequestedWhenSolvent() public {
        vm.prank(perp);
        uint256 paid = fund.coverShortfall(sink, 4 ether);
        assertEq(paid, 4 ether, "paid full");
        assertEq(sink.balance, 4 ether, "sink received");
    }

    function testCoverShortfallCapsAtBalanceAndEmitsBadDebt() public {
        vm.recordLogs();
        vm.prank(perp);
        uint256 paid = fund.coverShortfall(sink, 25 ether);
        assertEq(paid, 10 ether, "capped at balance");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool sawBadDebt;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == keccak256("BadDebt(uint256)")) sawBadDebt = true;
        }
        assertTrue(sawBadDebt, "BadDebt emitted");
    }

    function testOnlyPerpCanCover() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(InsuranceFund.OnlyPerp.selector);
        fund.coverShortfall(sink, 1 ether);
    }

    function testOwnerWithdrawsSurplus() public {
        vm.prank(owner);
        fund.withdraw(3 ether, sink);
        assertEq(sink.balance, 3 ether, "surplus withdrawn");
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `forge test --match-contract InsuranceFundTest`
Expected: FAIL — `InsuranceFund` does not exist.

- [ ] **Step 3: Write the implementation**

`src/InsuranceFund.sol`:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title InsuranceFund
/// @notice ETH backstop. Only the perp may draw, and only to cover settlement
///         shortfalls; uncovered amounts are surfaced via BadDebt, never silent.
contract InsuranceFund is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuard {
    address public perp;

    error OnlyPerp();
    error ZeroAddress();
    error EthTransferFailed();

    event Deposited(address indexed from, uint256 amount);
    event PerpSet(address perp);
    event ShortfallCovered(address indexed to, uint256 requested, uint256 paid);
    event BadDebt(uint256 uncovered);
    event Withdrawn(address indexed to, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner_) external initializer {
        if (owner_ == address(0)) revert ZeroAddress();
        __Ownable_init(owner_);
    }

    receive() external payable {
        emit Deposited(msg.sender, msg.value);
    }

    function deposit() external payable {
        emit Deposited(msg.sender, msg.value);
    }

    function setPerp(address perp_) external onlyOwner {
        if (perp_ == address(0)) revert ZeroAddress();
        perp = perp_;
        emit PerpSet(perp_);
    }

    function coverShortfall(address to, uint256 amount) external nonReentrant returns (uint256 paid) {
        if (msg.sender != perp) revert OnlyPerp();
        uint256 bal = address(this).balance;
        paid = amount > bal ? bal : amount;
        if (paid > 0) {
            (bool ok,) = to.call{value: paid}("");
            if (!ok) revert EthTransferFailed();
        }
        emit ShortfallCovered(to, amount, paid);
        if (amount > paid) emit BadDebt(amount - paid);
    }

    function withdraw(uint256 amount, address to) external onlyOwner nonReentrant {
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert EthTransferFailed();
        emit Withdrawn(to, amount);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `forge test --match-contract InsuranceFundTest`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add src/InsuranceFund.sol test/InsuranceFund.t.sol
git commit -m "feat: InsuranceFund bad-debt backstop"
```

---

## Task 5: PerpVault

**Files:**
- Create: `src/PerpVault.sol`
- Test: `test/PerpVault.t.sol`

- [ ] **Step 1: Write the failing test**

`test/PerpVault.t.sol`:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PerpVault} from "../src/PerpVault.sol";
import {TestBase} from "./TestBase.sol";

contract PerpVaultTest is TestBase {
    PerpVault internal vault;
    address internal owner = address(0xA11AD);
    address internal perp = address(0x9E97);
    address internal lp = address(0x11D);

    function setUp() public {
        PerpVault impl = new PerpVault();
        vault = PerpVault(payable(address(new ERC1967Proxy(address(impl), abi.encodeCall(PerpVault.initialize, (owner, 8000))))));
        vm.prank(owner);
        vault.setPerp(perp);
        vm.deal(lp, 100 ether);
        vm.deal(perp, 100 ether);
    }

    function testFirstDepositMintsSharesOneToOne() public {
        vm.prank(lp);
        uint256 shares = vault.deposit{value: 10 ether}();
        assertEq(shares, 10 ether, "1:1 first deposit");
        assertEq(vault.totalAssets(), 10 ether, "assets");
    }

    function testReserveRespectsUtilizationCap() public {
        vm.prank(lp);
        vault.deposit{value: 10 ether}();
        // cap = 80% of 10 = 8 ether
        vm.prank(perp);
        vm.expectRevert(PerpVault.UtilizationExceeded.selector);
        vault.reserve(9 ether);
        vm.prank(perp);
        vault.reserve(8 ether); // ok
        assertEq(vault.reserved(), 8 ether, "reserved");
    }

    function testWithdrawCannotTakeReserved() public {
        vm.prank(lp);
        uint256 shares = vault.deposit{value: 10 ether}();
        vm.prank(perp);
        vault.reserve(8 ether);
        vm.prank(lp);
        vm.expectRevert(PerpVault.InsufficientFreeAssets.selector);
        vault.withdraw(shares); // wants 10 but only 2 free
    }

    function testTakeLossRaisesSharePrice() public {
        vm.prank(lp);
        uint256 shares = vault.deposit{value: 10 ether}();
        vm.prank(perp);
        vault.takeLoss{value: 2 ether}();
        // now 12 ether backs `shares`; withdraw returns 12
        vm.prank(lp);
        uint256 out = vault.withdraw(shares);
        assertEq(out, 12 ether, "share price rose");
    }

    function testOnlyPerpGuards() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(PerpVault.OnlyPerp.selector);
        vault.reserve(1 ether);
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `forge test --match-contract PerpVaultTest`
Expected: FAIL — `PerpVault` does not exist.

- [ ] **Step 3: Write the implementation**

`src/PerpVault.sol`:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title PerpVault
/// @notice Pooled ETH LP house and counterparty to all perp positions. Holds LP
///         capital plus realized fees/PnL; trader margins live in IndexPerp.
contract PerpVault is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuard {
    uint256 public constant BPS = 10_000;
    uint256 public constant MAX_UTIL_CEILING = 10_000;

    address public perp;
    uint256 public totalShares;
    mapping(address lp => uint256 shares) public sharesOf;
    uint256 public reserved;
    uint256 public maxUtilBps;

    error ZeroAmount();
    error ZeroAddress();
    error OnlyPerp();
    error InsufficientShares();
    error InsufficientFreeAssets();
    error UtilizationExceeded();
    error EthTransferFailed();
    error ParamOutOfBounds();

    event Deposited(address indexed lp, uint256 ethIn, uint256 shares);
    event Withdrawn(address indexed lp, uint256 shares, uint256 ethOut);
    event Reserved(uint256 amount, uint256 totalReserved);
    event Released(uint256 amount, uint256 totalReserved);
    event ProfitPaid(address indexed to, uint256 amount);
    event LossTaken(uint256 amount);
    event PerpSet(address perp);
    event MaxUtilSet(uint256 maxUtilBps);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner_, uint256 maxUtilBps_) external initializer {
        if (owner_ == address(0)) revert ZeroAddress();
        if (maxUtilBps_ == 0 || maxUtilBps_ > MAX_UTIL_CEILING) revert ParamOutOfBounds();
        __Ownable_init(owner_);
        maxUtilBps = maxUtilBps_;
    }

    /// @dev Recapitalization (e.g. insurance top-up) raises share price.
    receive() external payable {}

    modifier onlyPerp() {
        if (msg.sender != perp) revert OnlyPerp();
        _;
    }

    function setPerp(address perp_) external onlyOwner {
        if (perp_ == address(0)) revert ZeroAddress();
        perp = perp_;
        emit PerpSet(perp_);
    }

    function totalAssets() public view returns (uint256) {
        return address(this).balance;
    }

    function freeAssets() public view returns (uint256) {
        uint256 bal = address(this).balance;
        return bal > reserved ? bal - reserved : 0;
    }

    function deposit() external payable nonReentrant returns (uint256 shares) {
        if (msg.value == 0) revert ZeroAmount();
        uint256 balBefore = address(this).balance - msg.value;
        shares = totalShares == 0 ? msg.value : (msg.value * totalShares) / balBefore;
        if (shares == 0) revert ZeroAmount();
        totalShares += shares;
        sharesOf[msg.sender] += shares;
        emit Deposited(msg.sender, msg.value, shares);
    }

    function withdraw(uint256 shares) external nonReentrant returns (uint256 ethOut) {
        if (shares == 0) revert ZeroAmount();
        if (sharesOf[msg.sender] < shares) revert InsufficientShares();
        ethOut = (shares * address(this).balance) / totalShares;
        if (ethOut > freeAssets()) revert InsufficientFreeAssets();
        sharesOf[msg.sender] -= shares;
        totalShares -= shares;
        (bool ok,) = msg.sender.call{value: ethOut}("");
        if (!ok) revert EthTransferFailed();
        emit Withdrawn(msg.sender, shares, ethOut);
    }

    function reserve(uint256 amount) external onlyPerp {
        uint256 newReserved = reserved + amount;
        if (newReserved > (address(this).balance * maxUtilBps) / BPS) revert UtilizationExceeded();
        reserved = newReserved;
        emit Reserved(amount, newReserved);
    }

    function release(uint256 amount) external onlyPerp {
        reserved = amount >= reserved ? 0 : reserved - amount;
        emit Released(amount, reserved);
    }

    function payProfit(address to, uint256 amount) external onlyPerp nonReentrant {
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert EthTransferFailed();
        emit ProfitPaid(to, amount);
    }

    function takeLoss() external payable onlyPerp {
        emit LossTaken(msg.value);
    }

    function setMaxUtilBps(uint256 v) external onlyOwner {
        if (v == 0 || v > MAX_UTIL_CEILING) revert ParamOutOfBounds();
        maxUtilBps = v;
        emit MaxUtilSet(v);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `forge test --match-contract PerpVaultTest`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add src/PerpVault.sol test/PerpVault.t.sol
git commit -m "feat: PerpVault pooled LP house"
```

---

## Task 6: IndexPerp — init + open

**Files:**
- Create: `src/IndexPerp.sol`
- Create: `test/IndexPerpTestBase.sol`
- Test: `test/IndexPerpOpen.t.sol`

- [ ] **Step 1: Write the shared test base**

`test/IndexPerpTestBase.sol`:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PushOracle} from "../src/PushOracle.sol";
import {IndexBasket} from "../src/IndexBasket.sol";
import {PerpVault} from "../src/PerpVault.sol";
import {InsuranceFund} from "../src/InsuranceFund.sol";
import {IndexPerp} from "../src/IndexPerp.sol";
import {TestBase} from "./TestBase.sol";

contract IndexPerpTestBase is TestBase {
    PushOracle internal oracle;
    IndexBasket internal basket;
    PerpVault internal vault;
    InsuranceFund internal insurance;
    IndexPerp internal perp;

    address internal owner = address(0xA11AD);
    address internal keeper = address(0xCAFE);
    address internal lp = address(0x11D);
    address internal trader = address(0x7AD);
    bytes32 internal constant FEED = bytes32("ETHUSDC");

    function _proxy(address impl, bytes memory initData) internal returns (address) {
        return address(new ERC1967Proxy(impl, initData));
    }

    function _deployStack() internal {
        oracle = PushOracle(_proxy(address(new PushOracle()), abi.encodeCall(PushOracle.initialize, (owner, keeper))));

        IndexBasket.IndexLeg[] memory legs = new IndexBasket.IndexLeg[](1);
        legs[0] = IndexBasket.IndexLeg({kind: IndexBasket.LegKind.CALL, strike: 2000e18, weight: 1e18});
        basket = IndexBasket(
            _proxy(
                address(new IndexBasket()),
                abi.encodeCall(IndexBasket.initialize, (owner, address(oracle), FEED, 1 hours, 2100e18, 10000e18, legs))
            )
        );

        vault = PerpVault(payable(_proxy(address(new PerpVault()), abi.encodeCall(PerpVault.initialize, (owner, 9000)))));
        insurance = InsuranceFund(payable(_proxy(address(new InsuranceFund()), abi.encodeCall(InsuranceFund.initialize, (owner)))));

        IndexPerp.InitParams memory p = IndexPerp.InitParams({
            owner: owner,
            basket: address(basket),
            vault: address(vault),
            insurance: address(insurance),
            maxLeverage: 20e18,
            openFeeBps: 10,
            closeFeeBps: 10,
            borrowBase: 0,
            fundK: 0,
            mmBps: 500,
            liqPenaltyBps: 500
        });
        perp = IndexPerp(payable(_proxy(address(new IndexPerp()), abi.encodeCall(IndexPerp.initialize, (p)))));
    }

    function _wire() internal {
        vm.prank(owner);
        vault.setPerp(address(perp));
        vm.prank(owner);
        insurance.setPerp(address(perp));
    }

    function _push(uint256 price) internal {
        vm.prank(keeper);
        oracle.pushPrice(FEED, price);
    }

    function _setUpPerp(uint256 lpEth, uint256 insEth, uint256 price) internal {
        _deployStack();
        _wire();
        vm.deal(lp, lpEth);
        vm.deal(trader, 1_000 ether);
        vm.deal(address(this), insEth);
        insurance.deposit{value: insEth}();
        vm.prank(lp);
        vault.deposit{value: lpEth}();
        vm.warp(1_000_000);
        _push(price);
    }
}
```

- [ ] **Step 2: Write the failing test**

`test/IndexPerpOpen.t.sol`:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IndexPerp} from "../src/IndexPerp.sol";
import {PerpVault} from "../src/PerpVault.sol";
import {IndexPerpTestBase} from "./IndexPerpTestBase.sol";

contract IndexPerpOpenTest is IndexPerpTestBase {
    function setUp() public {
        _setUpPerp(100 ether, 10 ether, 4000e18); // level = 0.5e18
    }

    function testOpenLongRecordsUnitsNotionalAndFee() public {
        // margin 1 ETH, 5x -> notional 5 ETH, openFee 10bps of 5 = 0.005, margin kept = 0.995
        // units = notional*ONE/level = 5e18 * 1e18 / 0.5e18 = 10e18
        vm.prank(trader);
        uint256 id = perp.open{value: 1 ether}(true, 5e18, type(uint256).max);
        (address o, bool isLong, uint256 units, uint256 entryLevel, uint256 margin,,,) = perp.positions(id);
        assertEq(o, trader, "owner");
        assertTrue(isLong, "long");
        assertEq(units, 10e18, "units");
        assertEq(entryLevel, 0.5e18, "entry level");
        assertEq(margin, 0.995 ether, "margin net of fee");
        assertEq(perp.longOI(), 5 ether, "longOI");
        assertEq(vault.reserved(), 5 ether, "reserved = notional");
    }

    function testOpenChargesOpenFeeToVault() public {
        uint256 before = vault.totalAssets();
        vm.prank(trader);
        perp.open{value: 1 ether}(true, 5e18, type(uint256).max);
        assertEq(vault.totalAssets() - before, 0.005 ether, "fee to vault");
    }

    function testOpenRevertsAboveMaxLeverage() public {
        vm.prank(trader);
        vm.expectRevert(IndexPerp.LeverageTooHigh.selector);
        perp.open{value: 1 ether}(true, 21e18, type(uint256).max);
    }

    function testOpenRevertsOnUtilizationCap() public {
        // cap = 90% of 100 = 90 ETH notional; 1 ETH @ 100x not allowed (maxLev 20), so use big margin
        vm.prank(trader);
        vm.expectRevert(PerpVault.UtilizationExceeded.selector);
        perp.open{value: 10 ether}(true, 20e18, type(uint256).max); // notional 200 > 90
    }

    function testOpenLongSlippageGuard() public {
        // limitLevel below current 0.5 -> long requires level <= limit -> revert
        vm.prank(trader);
        vm.expectRevert(IndexPerp.SlippageExceeded.selector);
        perp.open{value: 1 ether}(true, 5e18, 0.4e18);
    }

    function testOpenZeroMarginReverts() public {
        vm.prank(trader);
        vm.expectRevert(IndexPerp.ZeroMargin.selector);
        perp.open{value: 0}(true, 5e18, type(uint256).max);
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `forge test --match-contract IndexPerpOpenTest`
Expected: FAIL — `IndexPerp` does not exist.

- [ ] **Step 4: Write the implementation (init + open + views; close/liquidate added in Tasks 7–8)**

`src/IndexPerp.sol`:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {FundingMath} from "./FundingMath.sol";
import {IndexBasket} from "./IndexBasket.sol";
import {PerpVault} from "./PerpVault.sol";
import {InsuranceFund} from "./InsuranceFund.sol";

/// @title IndexPerp
/// @notice ETH-margined perpetual on an option-basket index, oracle-execution,
///         pooled LP vault counterparty. Fills at IndexBasket.currentLevel().
contract IndexPerp is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuard {
    uint256 public constant ONE = 1e18;
    uint256 public constant BPS = 10_000;
    uint256 public constant MAX_LEVERAGE_CEILING = 100e18;
    uint256 public constant MAX_FEE_BPS = 100; // 1%
    uint256 public constant MAX_MM_BPS = 5_000; // 50%
    uint256 public constant MAX_LIQ_PENALTY_BPS = 2_000; // 20%
    uint256 public constant MAX_BORROW_BASE = 1e15; // per-second, 1e18-scaled
    uint256 public constant MAX_FUND_K = 1e15;

    IndexBasket public basket;
    PerpVault public vault;
    InsuranceFund public insurance;

    uint256 public borrowCum; // monotonic
    int256 public fundingCum;
    uint64 public lastPoke;
    uint256 public longOI;
    uint256 public shortOI;

    uint256 public maxLeverage;
    uint256 public openFeeBps;
    uint256 public closeFeeBps;
    uint256 public borrowBase;
    uint256 public fundK;
    uint256 public mmBps;
    uint256 public liqPenaltyBps;

    struct Position {
        address owner;
        bool isLong;
        uint256 units;
        uint256 entryLevel;
        uint256 marginEth;
        uint256 entryBorrowCum;
        int256 entryFundingCum;
        uint64 openedAt;
    }

    mapping(uint256 id => Position) public positions;
    uint256 public nextId;

    struct InitParams {
        address owner;
        address basket;
        address vault;
        address insurance;
        uint256 maxLeverage;
        uint256 openFeeBps;
        uint256 closeFeeBps;
        uint256 borrowBase;
        uint256 fundK;
        uint256 mmBps;
        uint256 liqPenaltyBps;
    }

    error ZeroMargin();
    error LeverageTooHigh();
    error SlippageExceeded();
    error NotOwner();
    error PositionClosed();
    error NotLiquidatable();
    error ParamOutOfBounds();
    error EthTransferFailed();

    event Opened(uint256 indexed id, address indexed owner, bool isLong, uint256 units, uint256 entryLevel, uint256 marginEth);
    event Closed(uint256 indexed id, int256 pnl, uint256 payout);
    event MarginAdded(uint256 indexed id, uint256 amount);
    event Liquidated(uint256 indexed id, address indexed keeper, uint256 penalty);
    event Poked(uint256 borrowCum, int256 fundingCum);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    receive() external payable {} // accepts vault.payProfit(address(this)) during liquidation

    function initialize(InitParams calldata p) external initializer {
        __Ownable_init(p.owner);
        basket = IndexBasket(p.basket);
        vault = PerpVault(payable(p.vault));
        insurance = InsuranceFund(payable(p.insurance));
        _setParams(p.maxLeverage, p.openFeeBps, p.closeFeeBps, p.borrowBase, p.fundK, p.mmBps, p.liqPenaltyBps);
        lastPoke = uint64(block.timestamp);
        nextId = 1;
    }

    // ----------------------------------------------------------------- //
    // Accrual
    // ----------------------------------------------------------------- //

    function _poke() internal {
        uint256 dt = block.timestamp - lastPoke;
        if (dt == 0) return;
        borrowCum += FundingMath.borrowDelta(borrowBase, vault.reserved(), vault.totalAssets(), dt);
        fundingCum += FundingMath.fundingDelta(fundK, longOI, shortOI, dt);
        lastPoke = uint64(block.timestamp);
        emit Poked(borrowCum, fundingCum);
    }

    // ----------------------------------------------------------------- //
    // Open
    // ----------------------------------------------------------------- //

    function open(bool isLong, uint256 leverage, uint256 limitLevel)
        external
        payable
        nonReentrant
        returns (uint256 id)
    {
        if (msg.value == 0) revert ZeroMargin();
        if (leverage == 0 || leverage > maxLeverage) revert LeverageTooHigh();
        _poke();
        uint256 level = basket.currentLevel();
        if (isLong ? level > limitLevel : level < limitLevel) revert SlippageExceeded();

        uint256 notional = (leverage * msg.value) / ONE;
        uint256 units = (leverage * msg.value) / level;
        uint256 openFee = (notional * openFeeBps) / BPS;
        uint256 margin = msg.value - openFee;

        if (openFee > 0) vault.takeLoss{value: openFee}();
        vault.reserve(notional);

        if (isLong) longOI += notional;
        else shortOI += notional;

        id = nextId++;
        positions[id] = Position({
            owner: msg.sender,
            isLong: isLong,
            units: units,
            entryLevel: level,
            marginEth: margin,
            entryBorrowCum: borrowCum,
            entryFundingCum: fundingCum,
            openedAt: uint64(block.timestamp)
        });
        emit Opened(id, msg.sender, isLong, units, level, margin);
    }

    // ----------------------------------------------------------------- //
    // Params / upgrade
    // ----------------------------------------------------------------- //

    function setParams(
        uint256 maxLeverage_,
        uint256 openFeeBps_,
        uint256 closeFeeBps_,
        uint256 borrowBase_,
        uint256 fundK_,
        uint256 mmBps_,
        uint256 liqPenaltyBps_
    ) external onlyOwner {
        _setParams(maxLeverage_, openFeeBps_, closeFeeBps_, borrowBase_, fundK_, mmBps_, liqPenaltyBps_);
    }

    function _setParams(
        uint256 maxLeverage_,
        uint256 openFeeBps_,
        uint256 closeFeeBps_,
        uint256 borrowBase_,
        uint256 fundK_,
        uint256 mmBps_,
        uint256 liqPenaltyBps_
    ) internal {
        if (maxLeverage_ == 0 || maxLeverage_ > MAX_LEVERAGE_CEILING) revert ParamOutOfBounds();
        if (openFeeBps_ > MAX_FEE_BPS || closeFeeBps_ > MAX_FEE_BPS) revert ParamOutOfBounds();
        if (borrowBase_ > MAX_BORROW_BASE || fundK_ > MAX_FUND_K) revert ParamOutOfBounds();
        if (mmBps_ == 0 || mmBps_ > MAX_MM_BPS) revert ParamOutOfBounds();
        if (liqPenaltyBps_ > MAX_LIQ_PENALTY_BPS) revert ParamOutOfBounds();
        maxLeverage = maxLeverage_;
        openFeeBps = openFeeBps_;
        closeFeeBps = closeFeeBps_;
        borrowBase = borrowBase_;
        fundK = fundK_;
        mmBps = mmBps_;
        liqPenaltyBps = liqPenaltyBps_;
    }

    function _sendEth(address to, uint256 amount) internal {
        if (amount == 0) return;
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert EthTransferFailed();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `forge test --match-contract IndexPerpOpenTest`
Expected: PASS (6 tests).

- [ ] **Step 6: Commit**

```bash
git add src/IndexPerp.sol test/IndexPerpTestBase.sol test/IndexPerpOpen.t.sol
git commit -m "feat: IndexPerp init + open"
```

---

## Task 7: IndexPerp — close + addMargin

**Files:**
- Modify: `src/IndexPerp.sol` (add `close`, `addMargin`, `_settleMath`, `_disburseTo`, views)
- Test: `test/IndexPerpClose.t.sol`

- [ ] **Step 1: Write the failing test**

`test/IndexPerpClose.t.sol`:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IndexPerp} from "../src/IndexPerp.sol";
import {IndexPerpTestBase} from "./IndexPerpTestBase.sol";

contract IndexPerpCloseTest is IndexPerpTestBase {
    function setUp() public {
        // zero fees & funding for clean PnL assertions in this file:
        _setUpPerp(100 ether, 10 ether, 4000e18);
        vm.prank(owner);
        perp.setParams(20e18, 0, 0, 0, 0, 500, 500);
    }

    function _openLong1x5() internal returns (uint256 id) {
        vm.prank(trader);
        id = perp.open{value: 1 ether}(true, 5e18, type(uint256).max); // units 10e18, entry 0.5
    }

    function testLongProfitPaidFromVault() public {
        uint256 id = _openLong1x5();
        _push(5000e18); // level 0.6 -> pnl = units*(0.6-0.5) = 10e18*0.1e18/1e18 = 1 ETH
        uint256 balBefore = trader.balance;
        vm.prank(trader);
        int256 pnl = perp.close(id, 0);
        assertTrue(pnl == 1 ether, "pnl +1");
        // trader gets margin (1) + pnl (1) = 2 ETH
        assertEq(trader.balance - balBefore, 2 ether, "margin + profit");
    }

    function testLongLossGoesToVault() public {
        uint256 id = _openLong1x5();
        _push(3000e18); // level = 1 - 2000/3000 = 0.3333..; pnl negative
        uint256 vaultBefore = vault.totalAssets();
        uint256 balBefore = trader.balance;
        vm.prank(trader);
        perp.close(id, 0);
        // trader recovers less than margin; vault gains the loss
        assertTrue(trader.balance - balBefore < 1 ether, "trader recovers < margin");
        assertTrue(vault.totalAssets() > vaultBefore, "vault gained");
    }

    function testCloseReleasesReserveAndOI() public {
        uint256 id = _openLong1x5();
        _push(5000e18);
        vm.prank(trader);
        perp.close(id, 0);
        assertEq(vault.reserved(), 0, "reserve released");
        assertEq(perp.longOI(), 0, "OI cleared");
    }

    function testCloseSlippageGuard() public {
        uint256 id = _openLong1x5();
        _push(5000e18); // level 0.6
        vm.prank(trader);
        vm.expectRevert(IndexPerp.SlippageExceeded.selector);
        perp.close(id, 0.7e18); // long requires level >= limit; 0.6 < 0.7
    }

    function testOnlyOwnerCloses() public {
        uint256 id = _openLong1x5();
        _push(5000e18);
        vm.prank(address(0xBEEF));
        vm.expectRevert(IndexPerp.NotOwner.selector);
        perp.close(id, 0);
    }

    function testAddMarginIncreasesMargin() public {
        uint256 id = _openLong1x5();
        vm.prank(trader);
        perp.addMargin{value: 0.5 ether}(id);
        (,,,, uint256 margin,,,) = perp.positions(id);
        assertEq(margin, 1.5 ether, "margin increased");
    }

    function testShortProfitWhenLevelFalls() public {
        vm.prank(trader);
        uint256 id = perp.open{value: 1 ether}(false, 5e18, 0); // short, entry 0.5
        _push(3000e18); // level 0.3333 -> short pnl = units*(0.5-0.3333)
        uint256 balBefore = trader.balance;
        vm.prank(trader);
        int256 pnl = perp.close(id, type(uint256).max);
        assertTrue(pnl > 0, "short profits when level falls");
        assertTrue(trader.balance - balBefore > 1 ether, "margin + profit");
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `forge test --match-contract IndexPerpCloseTest`
Expected: FAIL — `close` / `addMargin` not defined.

- [ ] **Step 3: Add the implementation**

Insert into `src/IndexPerp.sol` after the `open` function (before the Params section):

```solidity
    // ----------------------------------------------------------------- //
    // Close / margin
    // ----------------------------------------------------------------- //

    function close(uint256 id, uint256 limitLevel) external nonReentrant returns (int256 pnl) {
        Position memory pos = positions[id];
        if (pos.owner == address(0)) revert PositionClosed();
        if (pos.owner != msg.sender) revert NotOwner();
        _poke();
        uint256 level = basket.currentLevel();
        if (pos.isLong ? level < limitLevel : level > limitLevel) revert SlippageExceeded();

        (int256 pnl_, uint256 borrowOwed, int256 fundOwed, uint256 notional) = _settleMath(pos, level);
        pnl = pnl_;
        uint256 closeFee = (((pos.units * level) / ONE) * closeFeeBps) / BPS;

        int256 settle =
            int256(pos.marginEth) + pnl - int256(borrowOwed) - fundOwed - int256(closeFee);
        int256 vaultDelta = -pnl + int256(borrowOwed) + fundOwed + int256(closeFee);

        if (pos.isLong) longOI -= notional;
        else shortOI -= notional;
        vault.release(notional);
        delete positions[id];

        uint256 payout = _disburseTo(pos.owner, pos.marginEth, settle, vaultDelta);
        emit Closed(id, pnl, payout);
    }

    function addMargin(uint256 id) external payable nonReentrant {
        Position storage pos = positions[id];
        if (pos.owner == address(0)) revert PositionClosed();
        if (pos.owner != msg.sender) revert NotOwner();
        if (msg.value == 0) revert ZeroMargin();
        pos.marginEth += msg.value;
        emit MarginAdded(id, msg.value);
    }

    // ----------------------------------------------------------------- //
    // Settlement math + disbursement
    // ----------------------------------------------------------------- //

    function _settleMath(Position memory pos, uint256 level)
        internal
        view
        returns (int256 pnl, uint256 borrowOwed, int256 fundOwed, uint256 notional)
    {
        notional = (pos.units * pos.entryLevel) / ONE;
        uint256 markValue = (pos.units * level) / ONE;
        pnl = pos.isLong ? int256(markValue) - int256(notional) : int256(notional) - int256(markValue);
        borrowOwed = (notional * (borrowCum - pos.entryBorrowCum)) / ONE;
        int256 fundDiff = fundingCum - pos.entryFundingCum;
        int256 raw = (int256(notional) * fundDiff) / int256(ONE);
        fundOwed = pos.isLong ? raw : -raw;
    }

    /// @dev Routes ETH for a closing position. `recipient == address(this)` keeps the
    ///      trader payout inside the perp (used by liquidation to skim a penalty).
    ///      Returns the gross ETH owed to the trader before any penalty.
    function _disburseTo(address recipient, uint256 margin, int256 settle, int256 vaultDelta)
        internal
        returns (uint256 grossToRecipient)
    {
        if (settle < 0) {
            if (margin > 0) vault.takeLoss{value: margin}();
            insurance.coverShortfall(address(vault), uint256(-settle));
            return 0;
        }
        if (vaultDelta >= 0) {
            uint256 vd = uint256(vaultDelta);
            if (vd > 0) vault.takeLoss{value: vd}();
            grossToRecipient = margin - vd; // == uint256(settle)
            if (recipient != address(this)) _sendEth(recipient, grossToRecipient);
        } else {
            uint256 owed = uint256(-vaultDelta);
            vault.payProfit(address(this), owed);
            grossToRecipient = margin + owed;
            if (recipient != address(this)) _sendEth(recipient, grossToRecipient);
        }
    }

    function notionalOf(uint256 id) external view returns (uint256) {
        Position storage pos = positions[id];
        return (pos.units * pos.entryLevel) / ONE;
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `forge test --match-contract IndexPerpCloseTest`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add src/IndexPerp.sol test/IndexPerpClose.t.sol
git commit -m "feat: IndexPerp close + addMargin"
```

---

## Task 8: IndexPerp — liquidate + funding/borrow accrual

**Files:**
- Modify: `src/IndexPerp.sol` (add `liquidate`, `equityOf`)
- Test: `test/IndexPerpLiquidation.t.sol`, `test/IndexPerpFunding.t.sol`

- [ ] **Step 1: Write the failing liquidation test**

`test/IndexPerpLiquidation.t.sol`:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IndexPerp} from "../src/IndexPerp.sol";
import {IndexPerpTestBase} from "./IndexPerpTestBase.sol";

contract IndexPerpLiquidationTest is IndexPerpTestBase {
    address internal liquidator = address(0x4140);

    function setUp() public {
        _setUpPerp(100 ether, 10 ether, 4000e18);
        vm.prank(owner);
        perp.setParams(20e18, 0, 0, 0, 0, 500, 500); // mm 5%, liq penalty 5%, no fees
        vm.deal(liquidator, 1 ether);
    }

    function testHealthyPositionNotLiquidatable() public {
        vm.prank(trader);
        uint256 id = perp.open{value: 1 ether}(true, 5e18, type(uint256).max);
        vm.prank(liquidator);
        vm.expectRevert(IndexPerp.NotLiquidatable.selector);
        perp.liquidate(id);
    }

    function testUnderwaterLongIsLiquidatedWithPenalty() public {
        // 10x long: margin 1, notional 10, units 20e18 (entry 0.5). mm = 5% of 10 = 0.5
        vm.prank(trader);
        uint256 id = perp.open{value: 1 ether}(true, 10e18, type(uint256).max);
        // drop level so equity < 0.5. level 0.45 -> pnl = 20e18*(0.45-0.5) = -1 ETH; equity = 1-1 = 0 < 0.5
        _push(3636363636363636363637); // ~1 - 2000/3636.36 = 0.45
        uint256 keeperBefore = liquidator.balance;
        vm.prank(liquidator);
        uint256 penalty = perp.liquidate(id);
        assertTrue(penalty > 0, "penalty charged");
        assertTrue(liquidator.balance > keeperBefore, "keeper rewarded");
        (address o,,,,,,,) = perp.positions(id);
        assertEq(o, address(0), "position cleared");
        assertEq(vault.reserved(), 0, "reserve released");
    }
}
```

- [ ] **Step 2: Write the failing funding test**

`test/IndexPerpFunding.t.sol`:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IndexPerp} from "../src/IndexPerp.sol";
import {IndexPerpTestBase} from "./IndexPerpTestBase.sol";

contract IndexPerpFundingTest is IndexPerpTestBase {
    function setUp() public {
        _setUpPerp(100 ether, 10 ether, 4000e18);
        // enable borrow + funding
        vm.prank(owner);
        perp.setParams(20e18, 0, 0, 1e9, 1e9, 500, 500);
    }

    function testBorrowAccrualReducesLongSettlement() public {
        vm.prank(trader);
        uint256 id = perp.open{value: 1 ether}(true, 5e18, type(uint256).max); // notional 5
        uint256 t0 = block.timestamp;
        vm.warp(t0 + 1000);
        _push(4000e18); // same level -> zero pnl, so any shortfall is pure borrow fee
        uint256 balBefore = trader.balance;
        vm.prank(trader);
        perp.close(id, 0);
        assertTrue(trader.balance - balBefore < 1 ether, "borrow fee reduced payout");
    }

    function testLongHeavyFundingChargesLong() public {
        // open a large long and small short so skew is long-heavy
        vm.prank(trader);
        uint256 longId = perp.open{value: 4 ether}(true, 5e18, type(uint256).max); // notional 20
        vm.prank(trader);
        perp.open{value: 1 ether}(false, 5e18, 0); // notional 5 short
        vm.warp(block.timestamp + 1000);
        _push(4000e18); // unchanged level
        uint256 balBefore = trader.balance;
        vm.prank(trader);
        perp.close(longId, 0); // long pays funding + borrow -> payout < margin
        assertTrue(trader.balance - balBefore < 4 ether, "long-heavy: long pays");
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `forge test --match-contract IndexPerpLiquidationTest` then `forge test --match-contract IndexPerpFundingTest`
Expected: FAIL — `liquidate` not defined.

- [ ] **Step 4: Add the implementation**

Insert into `src/IndexPerp.sol` after `addMargin`:

```solidity
    function equityOf(uint256 id, uint256 level) public view returns (int256 equity, uint256 notional) {
        Position memory pos = positions[id];
        (int256 pnl, uint256 borrowOwed, int256 fundOwed, uint256 n) = _settleMath(pos, level);
        notional = n;
        equity = int256(pos.marginEth) + pnl - int256(borrowOwed) - fundOwed;
    }

    function liquidate(uint256 id) external nonReentrant returns (uint256 penalty) {
        Position memory pos = positions[id];
        if (pos.owner == address(0)) revert PositionClosed();
        _poke();
        uint256 level = basket.currentLevel();

        (int256 pnl, uint256 borrowOwed, int256 fundOwed, uint256 notional) = _settleMath(pos, level);
        int256 equity = int256(pos.marginEth) + pnl - int256(borrowOwed) - fundOwed;
        if (equity >= int256((notional * mmBps) / BPS)) revert NotLiquidatable();

        penalty = (notional * liqPenaltyBps) / BPS;

        int256 settle = equity; // no close fee on liquidation; penalty taken instead
        int256 vaultDelta = -pnl + int256(borrowOwed) + fundOwed;

        if (pos.isLong) longOI -= notional;
        else shortOI -= notional;
        vault.release(notional);
        address posOwner = pos.owner;
        delete positions[id];

        // Bring trader's gross equity (if any) into this contract, then skim penalty.
        uint256 gross = _disburseTo(address(this), pos.marginEth, settle, vaultDelta);
        uint256 pen = penalty > gross ? gross : penalty;
        uint256 keeperReward = pen / 2;
        uint256 insCut = pen - keeperReward;
        if (keeperReward > 0) _sendEth(msg.sender, keeperReward);
        if (insCut > 0) _sendEth(address(insurance), insCut);
        uint256 traderGets = gross - pen;
        if (traderGets > 0) _sendEth(posOwner, traderGets);

        emit Liquidated(id, msg.sender, penalty);
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `forge test --match-contract IndexPerpLiquidationTest` then `forge test --match-contract IndexPerpFundingTest`
Expected: PASS (3 + 2 tests).

- [ ] **Step 6: Commit**

```bash
git add src/IndexPerp.sol test/IndexPerpLiquidation.t.sol test/IndexPerpFunding.t.sol
git commit -m "feat: IndexPerp liquidation + funding/borrow accrual"
```

---

## Task 9: Fuzz + solvency tests

**Files:**
- Test: `test/IndexPerpFuzz.t.sol`, `test/IndexPerpSolvency.t.sol`

- [ ] **Step 1: Write the fuzz test (ETH conservation on open→close)**

`test/IndexPerpFuzz.t.sol`:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IndexPerpTestBase} from "./IndexPerpTestBase.sol";

contract IndexPerpFuzzTest is IndexPerpTestBase {
    function setUp() public {
        _setUpPerp(1_000 ether, 100 ether, 4000e18);
        vm.prank(owner);
        perp.setParams(20e18, 10, 10, 1e8, 1e8, 500, 500);
    }

    /// Total ETH across perp + vault + insurance + trader is conserved across an
    /// open→(price move)→close round-trip (no ETH created or destroyed).
    function testFuzzOpenCloseConservesEth(uint96 marginRaw, uint16 levRaw, uint96 priceRaw, bool isLong) public {
        uint256 margin = (uint256(marginRaw) % 5 ether) + 0.01 ether;
        uint256 leverage = ((uint256(levRaw) % 19) + 1) * 1e18; // 1x..20x
        uint256 price = (uint256(priceRaw) % 7000e18) + 2200e18; // 2200..9200, all > strike+band

        uint256 totalBefore = address(perp).balance + vault.totalAssets() + address(insurance).balance + trader.balance;

        vm.prank(trader);
        try perp.open{value: margin}(isLong, leverage, isLong ? type(uint256).max : 0) returns (uint256 id) {
            vm.warp(block.timestamp + (uint256(priceRaw) % 5000));
            _push(price);
            vm.prank(trader);
            try perp.close(id, isLong ? 0 : type(uint256).max) {} catch {}
        } catch {}

        uint256 totalAfter = address(perp).balance + vault.totalAssets() + address(insurance).balance + trader.balance;
        // allow tiny rounding dust (<= 1e6 wei)
        if (totalAfter > totalBefore) {
            assertLe(totalAfter - totalBefore, 1e6, "no ETH created");
        } else {
            assertLe(totalBefore - totalAfter, 1e6, "no ETH destroyed");
        }
    }
}
```

- [ ] **Step 2: Write the solvency test**

`test/IndexPerpSolvency.t.sol`:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IndexPerpTestBase} from "./IndexPerpTestBase.sol";

contract IndexPerpSolvencyTest is IndexPerpTestBase {
    function setUp() public {
        _setUpPerp(1_000 ether, 100 ether, 4000e18);
        vm.prank(owner);
        perp.setParams(20e18, 10, 10, 1e8, 1e8, 500, 500);
    }

    /// After any sequence of opens at varied prices, vault balance never drops below
    /// its reserved amount (LP reserved capital is never spent on open).
    function testFuzzVaultBalanceCoversReserved(uint96 a, uint96 b, uint96 c) public {
        uint256[3] memory margins = [(uint256(a) % 3 ether) + 0.1 ether, (uint256(b) % 3 ether) + 0.1 ether, (uint256(c) % 3 ether) + 0.1 ether];
        for (uint256 i; i < 3; ++i) {
            vm.prank(trader);
            try perp.open{value: margins[i]}(i % 2 == 0, 5e18, type(uint256).max) {} catch {}
        }
        assertTrue(vault.totalAssets() >= vault.reserved(), "vault covers reserved");
    }
}
```

- [ ] **Step 3: Run tests**

Run: `forge test --match-contract IndexPerpFuzzTest` then `forge test --match-contract IndexPerpSolvencyTest`
Expected: PASS (default 256 runs each).

- [ ] **Step 4: Commit**

```bash
git add test/IndexPerpFuzz.t.sol test/IndexPerpSolvency.t.sol
git commit -m "test: IndexPerp ETH-conservation fuzz + solvency"
```

---

## Task 10: UUPS upgradeability tests + deploy script

**Files:**
- Test: `test/IndexPerpUpgradeability.t.sol`
- Create: `script/DeployIndexPerp.s.sol`

- [ ] **Step 1: Write upgradeability test**

`test/IndexPerpUpgradeability.t.sol`:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IndexPerp} from "../src/IndexPerp.sol";
import {PerpVault} from "../src/PerpVault.sol";
import {IndexPerpTestBase} from "./IndexPerpTestBase.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract IndexPerpUpgradeabilityTest is IndexPerpTestBase {
    bytes32 internal constant IMPL_SLOT = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

    function setUp() public {
        _setUpPerp(100 ether, 10 ether, 4000e18);
    }

    function _impl(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, IMPL_SLOT))));
    }

    function testOwnerCanUpgradePerp() public {
        address newImpl = address(new IndexPerp());
        vm.prank(owner);
        UUPSUpgradeable(address(perp)).upgradeToAndCall(newImpl, "");
        assertEq(_impl(address(perp)), newImpl, "impl swapped");
    }

    function testNonOwnerCannotUpgradePerp() public {
        address newImpl = address(new IndexPerp());
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        UUPSUpgradeable(address(perp)).upgradeToAndCall(newImpl, "");
    }

    function testNonOwnerCannotUpgradeVault() public {
        address newImpl = address(new PerpVault());
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        UUPSUpgradeable(address(vault)).upgradeToAndCall(newImpl, "");
    }
}
```

- [ ] **Step 2: Run it (red, then it should pass since upgrade auth already implemented)**

Run: `forge test --match-contract IndexPerpUpgradeabilityTest`
Expected: PASS (3 tests) — confirms `_authorizeUpgrade` onlyOwner across the stack.

- [ ] **Step 3: Write the deploy script**

`script/DeployIndexPerp.s.sol`:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Script, console2} from "forge-std/Script.sol";
import {PushOracle} from "../src/PushOracle.sol";
import {IndexBasket} from "../src/IndexBasket.sol";
import {PerpVault} from "../src/PerpVault.sol";
import {InsuranceFund} from "../src/InsuranceFund.sol";
import {IndexPerp} from "../src/IndexPerp.sol";

/// @notice Deploys and wires one full Index Perp stack with a seed CALL@2000 basket.
contract DeployIndexPerp is Script {
    bytes32 internal constant FEED = bytes32("ETHUSDC");

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address admin = vm.envOr("UPGRADE_ADMIN", vm.addr(pk));
        address keeper = vm.envOr("KEEPER", vm.addr(pk));

        vm.startBroadcast(pk);

        PushOracle oracle = PushOracle(
            address(new ERC1967Proxy(address(new PushOracle()), abi.encodeCall(PushOracle.initialize, (admin, keeper))))
        );

        IndexBasket.IndexLeg[] memory legs = new IndexBasket.IndexLeg[](1);
        legs[0] = IndexBasket.IndexLeg({kind: IndexBasket.LegKind.CALL, strike: 2000e18, weight: 1e18});
        IndexBasket basket = IndexBasket(
            address(
                new ERC1967Proxy(
                    address(new IndexBasket()),
                    abi.encodeCall(
                        IndexBasket.initialize, (admin, address(oracle), FEED, 1 hours, 2100e18, 10000e18, legs)
                    )
                )
            )
        );

        PerpVault vault = PerpVault(
            payable(address(new ERC1967Proxy(address(new PerpVault()), abi.encodeCall(PerpVault.initialize, (admin, 9000)))))
        );
        InsuranceFund insurance = InsuranceFund(
            payable(address(new ERC1967Proxy(address(new InsuranceFund()), abi.encodeCall(InsuranceFund.initialize, (admin)))))
        );

        IndexPerp.InitParams memory p = IndexPerp.InitParams({
            owner: admin,
            basket: address(basket),
            vault: address(vault),
            insurance: address(insurance),
            maxLeverage: 20e18,
            openFeeBps: 10,
            closeFeeBps: 10,
            borrowBase: 1e8,
            fundK: 1e8,
            mmBps: 500,
            liqPenaltyBps: 500
        });
        IndexPerp perp = IndexPerp(
            payable(address(new ERC1967Proxy(address(new IndexPerp()), abi.encodeCall(IndexPerp.initialize, (p)))))
        );

        vault.setPerp(address(perp));
        insurance.setPerp(address(perp));

        vm.stopBroadcast();

        console2.log("PUSH_ORACLE", address(oracle));
        console2.log("INDEX_BASKET", address(basket));
        console2.log("PERP_VAULT", address(vault));
        console2.log("INSURANCE_FUND", address(insurance));
        console2.log("INDEX_PERP", address(perp));
    }
}
```

- [ ] **Step 4: Build + full test run**

Run: `forge build` then `forge test`
Expected: build OK; all suites PASS.

- [ ] **Step 5: Commit**

```bash
git add test/IndexPerpUpgradeability.t.sol script/DeployIndexPerp.s.sol
git commit -m "feat: Index Perp UUPS upgrade tests + deploy script"
```

---

## Self-review (completed by plan author)

**Spec coverage:** PushOracle (§4.1) → T1; IndexBasket (§4.2) → T2; PerpVault (§4.3) → T5; FundingMath (§4.4) → T3; IndexPerp open/close/addMargin/liquidate (§4.5) → T6–T8; InsuranceFund (§4.6) → T4; params/bounds (§4.7) → T6 `_setParams`; error handling (§5) → per-contract tests; security invariants (§6) → T9 conservation + solvency; test matrix (§7) → T1–T10 (note: invariants implemented as `testFuzz*` solvency checks, matching the repo's no-StdInvariant convention); deploy wiring (§8) → T10. All spec sections covered.

**Placeholder scan:** None. (An earlier `IndexPerpTestBase` drafting artifact was removed so all code blocks are copy-paste clean.)

**Type consistency:** `InitParams` fields match between `IndexPerp.initialize`, `IndexPerpTestBase`, and `DeployIndexPerp`. `positions(id)` tuple order (owner, isLong, units, entryLevel, marginEth, entryBorrowCum, entryFundingCum, openedAt) matches the destructuring in tests. `_disburseTo`/`_settleMath` signatures match call sites. Leg struct `{kind, strike, weight}` consistent across basket, tests, script.

**Note for implementer:** run `forge build` after T6 (first IndexPerp task) to confirm the stack compiles before layering close/liquidate.

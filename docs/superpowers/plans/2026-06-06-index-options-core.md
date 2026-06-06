# Index Options Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a self-contained Foundry prototype of the ETH-backed P/N option primitive from the approved design.

**Architecture:** The project has one `OptionSeries` contract per option market. Each series owns ETH collateral and deploys two restricted-mint ERC20 claim tokens, P and N. Settlement reads a resolved fixed-point value from `IPriceOracle`, computes complementary payouts, and lets P and N holders redeem independently.

**Tech Stack:** Foundry, Solidity `0.8.24`, self-contained ERC20 implementation, self-contained Solidity test harness using Foundry cheatcodes.

---

## File Structure

- Create `.gitignore`: ignores Foundry build outputs and local editor artifacts.
- Create `foundry.toml`: Foundry profile with Solidity `0.8.24`.
- Create `src/ClaimToken.sol`: minimal ERC20 claim token; only its owning series can mint and burn.
- Create `src/interfaces/IPriceOracle.sol`: oracle interface used by `OptionSeries`.
- Create `src/OptionSeries.sol`: core split, combine, settle, redeem lifecycle.
- Create `src/OptionFactory.sol`: deploys configured option series and emits creation events.
- Create `test/TestBase.sol`: local assertion helpers and Foundry cheatcode interface.
- Create `test/mocks/MockPriceOracle.sol`: test-only oracle that stores resolved values by series address.
- Create `test/ClaimToken.t.sol`: token unit tests.
- Create `test/OptionSeriesSplitCombine.t.sol`: split/combine lifecycle tests.
- Create `test/OptionSeriesSettlement.t.sol`: settlement and redemption tests.
- Create `test/OptionFactory.t.sol`: factory deployment tests.

---

### Task 1: Foundry Scaffold And Test Harness

**Files:**
- Create: `.gitignore`
- Create: `foundry.toml`
- Create: `test/TestBase.sol`

- [ ] **Step 1: Create the Foundry config and local test harness**

```solidity
// test/TestBase.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface Vm {
    function warp(uint256 newTimestamp) external;
    function deal(address account, uint256 newBalance) external;
    function prank(address account) external;
    function expectRevert(bytes4 selector) external;
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData) external;
}

contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    receive() external payable {}

    function assertTrue(bool value, string memory message) internal pure {
        if (!value) revert(message);
    }

    function assertFalse(bool value, string memory message) internal pure {
        if (value) revert(message);
    }

    function assertEq(uint256 actual, uint256 expected, string memory message) internal pure {
        if (actual != expected) revert(message);
    }

    function assertEq(address actual, address expected, string memory message) internal pure {
        if (actual != expected) revert(message);
    }

    function assertLe(uint256 actual, uint256 expected, string memory message) internal pure {
        if (actual > expected) revert(message);
    }

    function assertStrEq(string memory actual, string memory expected, string memory message) internal pure {
        if (keccak256(bytes(actual)) != keccak256(bytes(expected))) revert(message);
    }
}
```

```toml
# foundry.toml
[profile.default]
src = "src"
out = "out"
libs = []
test = "test"
solc_version = "0.8.24"
optimizer = true
optimizer_runs = 200
```

```gitignore
# .gitignore
out/
cache/
broadcast/
*.swp
.DS_Store
```

- [ ] **Step 2: Run the empty test suite**

Run:

```bash
forge test
```

Expected: command succeeds with no compiled test contracts or no tests executed.

- [ ] **Step 3: Commit the scaffold**

```bash
git add .gitignore foundry.toml test/TestBase.sol
git commit -m "chore: scaffold foundry project"
```

---

### Task 2: ClaimToken

**Files:**
- Create: `src/ClaimToken.sol`
- Create: `test/ClaimToken.t.sol`

- [ ] **Step 1: Write failing ClaimToken tests**

```solidity
// test/ClaimToken.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ClaimToken } from "../src/ClaimToken.sol";
import { TestBase } from "./TestBase.sol";

contract ClaimTokenTest is TestBase {
    ClaimToken internal token;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCA20);

    function setUp() public {
        token = new ClaimToken("P USD/ETH", "pUSD");
    }

    function testSeriesCanMintAndBurn() public {
        token.mint(alice, 5 ether);

        assertEq(token.totalSupply(), 5 ether, "total supply after mint");
        assertEq(token.balanceOf(alice), 5 ether, "alice balance after mint");

        token.burn(alice, 2 ether);

        assertEq(token.totalSupply(), 3 ether, "total supply after burn");
        assertEq(token.balanceOf(alice), 3 ether, "alice balance after burn");
    }

    function testNonSeriesCannotMint() public {
        vm.expectRevert(ClaimToken.Unauthorized.selector);
        vm.prank(alice);
        token.mint(alice, 1 ether);
    }

    function testTransferAndTransferFrom() public {
        token.mint(alice, 10 ether);

        vm.prank(alice);
        token.transfer(bob, 3 ether);

        assertEq(token.balanceOf(alice), 7 ether, "alice balance after transfer");
        assertEq(token.balanceOf(bob), 3 ether, "bob balance after transfer");

        vm.prank(bob);
        token.approve(carol, 1 ether);

        vm.prank(carol);
        token.transferFrom(bob, alice, 1 ether);

        assertEq(token.balanceOf(alice), 8 ether, "alice balance after transferFrom");
        assertEq(token.balanceOf(bob), 2 ether, "bob balance after transferFrom");
        assertEq(token.allowance(bob, carol), 0, "allowance after transferFrom");
    }
}
```

- [ ] **Step 2: Run the ClaimToken tests and verify they fail**

Run:

```bash
forge test --match-contract ClaimTokenTest -vvv
```

Expected: FAIL because `src/ClaimToken.sol` does not exist.

- [ ] **Step 3: Implement ClaimToken**

```solidity
// src/ClaimToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract ClaimToken {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    address public immutable series;
    uint256 public totalSupply;

    mapping(address account => uint256 balance) public balanceOf;
    mapping(address owner => mapping(address spender => uint256 amount)) public allowance;

    error Unauthorized();
    error InsufficientBalance();
    error InsufficientAllowance();
    error InvalidRecipient();

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
        series = msg.sender;
    }

    modifier onlySeries() {
        if (msg.sender != series) revert Unauthorized();
        _;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < amount) revert InsufficientAllowance();
            unchecked {
                allowance[from][msg.sender] = allowed - amount;
            }
            emit Approval(from, msg.sender, allowance[from][msg.sender]);
        }

        _transfer(from, to, amount);
        return true;
    }

    function mint(address to, uint256 amount) external onlySeries {
        if (to == address(0)) revert InvalidRecipient();

        totalSupply += amount;
        balanceOf[to] += amount;

        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external onlySeries {
        uint256 balance = balanceOf[from];
        if (balance < amount) revert InsufficientBalance();

        unchecked {
            balanceOf[from] = balance - amount;
            totalSupply -= amount;
        }

        emit Transfer(from, address(0), amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        if (to == address(0)) revert InvalidRecipient();

        uint256 balance = balanceOf[from];
        if (balance < amount) revert InsufficientBalance();

        unchecked {
            balanceOf[from] = balance - amount;
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);
    }
}
```

- [ ] **Step 4: Run the ClaimToken tests and verify they pass**

Run:

```bash
forge test --match-contract ClaimTokenTest -vvv
```

Expected: PASS, 3 tests.

- [ ] **Step 5: Commit ClaimToken**

```bash
git add src/ClaimToken.sol test/ClaimToken.t.sol
git commit -m "feat: add restricted claim token"
```

---

### Task 3: OptionSeries Split And Combine

**Files:**
- Create: `src/interfaces/IPriceOracle.sol`
- Create: `src/OptionSeries.sol`
- Create: `test/mocks/MockPriceOracle.sol`
- Create: `test/OptionSeriesSplitCombine.t.sol`

- [ ] **Step 1: Write failing split/combine tests**

```solidity
// test/OptionSeriesSplitCombine.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ClaimToken } from "../src/ClaimToken.sol";
import { OptionSeries } from "../src/OptionSeries.sol";
import { MockPriceOracle } from "./mocks/MockPriceOracle.sol";
import { TestBase } from "./TestBase.sol";

contract OptionSeriesSplitCombineTest is TestBase {
    MockPriceOracle internal oracle;
    OptionSeries internal series;
    ClaimToken internal pToken;
    ClaimToken internal nToken;
    address internal alice = address(0xA11CE);
    uint256 internal maturity;

    function setUp() public {
        oracle = new MockPriceOracle();
        maturity = block.timestamp + 7 days;
        series = new OptionSeries(
            "USD/ETH",
            2000e18,
            maturity,
            address(oracle),
            "P USD/ETH 2000",
            "pUSD2000",
            "N USD/ETH 2000",
            "nUSD2000"
        );
        pToken = series.pToken();
        nToken = series.nToken();
        vm.deal(alice, 10 ether);
    }

    function testSplitMintsEqualClaimsAndStoresCollateral() public {
        vm.prank(alice);
        series.split{ value: 2 ether }(alice);

        assertEq(address(series).balance, 2 ether, "series collateral");
        assertEq(pToken.balanceOf(alice), 2 ether, "alice P balance");
        assertEq(nToken.balanceOf(alice), 2 ether, "alice N balance");
        assertEq(pToken.totalSupply(), 2 ether, "P supply");
        assertEq(nToken.totalSupply(), 2 ether, "N supply");
    }

    function testCombineBurnsClaimsAndReturnsEthBeforeMaturity() public {
        vm.prank(alice);
        series.split{ value: 2 ether }(alice);

        uint256 balanceBeforeCombine = alice.balance;

        vm.prank(alice);
        series.combine(1 ether, alice);

        assertEq(alice.balance, balanceBeforeCombine + 1 ether, "alice receives ETH");
        assertEq(address(series).balance, 1 ether, "remaining collateral");
        assertEq(pToken.balanceOf(alice), 1 ether, "remaining P");
        assertEq(nToken.balanceOf(alice), 1 ether, "remaining N");
        assertEq(pToken.totalSupply(), 1 ether, "remaining P supply");
        assertEq(nToken.totalSupply(), 1 ether, "remaining N supply");
    }

    function testSplitRejectsZeroAmount() public {
        vm.expectRevert(OptionSeries.ZeroAmount.selector);
        vm.prank(alice);
        series.split{ value: 0 }(alice);
    }

    function testSplitRejectedAtMaturity() public {
        vm.warp(maturity);

        vm.expectRevert(OptionSeries.SplitAfterMaturity.selector);
        vm.prank(alice);
        series.split{ value: 1 ether }(alice);
    }

    function testCombineAllowedAfterMaturityBeforeSettlement() public {
        vm.prank(alice);
        series.split{ value: 1 ether }(alice);

        vm.warp(maturity);
        uint256 balanceBeforeCombine = alice.balance;

        vm.prank(alice);
        series.combine(1 ether, alice);

        assertEq(alice.balance, balanceBeforeCombine + 1 ether, "alice receives ETH after maturity");
        assertEq(address(series).balance, 0, "series collateral after combine");
    }
}
```

```solidity
// test/mocks/MockPriceOracle.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IPriceOracle } from "../../src/interfaces/IPriceOracle.sol";

contract MockPriceOracle is IPriceOracle {
    struct Resolution {
        bool resolved;
        uint256 value;
    }

    mapping(address series => Resolution resolution) internal resolutions;

    function setResolvedValue(address series, uint256 value) external {
        resolutions[series] = Resolution({ resolved: true, value: value });
    }

    function clearResolvedValue(address series) external {
        delete resolutions[series];
    }

    function getResolvedValue(address series) external view returns (bool resolved, uint256 value) {
        Resolution storage resolution = resolutions[series];
        return (resolution.resolved, resolution.value);
    }
}
```

- [ ] **Step 2: Run split/combine tests and verify they fail**

Run:

```bash
forge test --match-contract OptionSeriesSplitCombineTest -vvv
```

Expected: FAIL because `OptionSeries` and `IPriceOracle` do not exist.

- [ ] **Step 3: Implement oracle interface and OptionSeries split/combine shell**

```solidity
// src/interfaces/IPriceOracle.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPriceOracle {
    function getResolvedValue(address series) external view returns (bool resolved, uint256 value);
}
```

```solidity
// src/OptionSeries.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ClaimToken } from "./ClaimToken.sol";
import { IPriceOracle } from "./interfaces/IPriceOracle.sol";

contract OptionSeries {
    uint256 public constant ONE = 1e18;

    string public ticker;
    uint256 public immutable strike;
    uint256 public immutable maturity;
    IPriceOracle public immutable oracle;
    ClaimToken public immutable pToken;
    ClaimToken public immutable nToken;

    bool public settled;

    error ZeroStrike();
    error ZeroMaturity();
    error ZeroOracle();
    error ZeroAmount();
    error SplitAfterMaturity();
    error CombineAfterSettlement();
    error SettleBeforeMaturity();
    error OracleUnresolved();
    error InvalidOracleValue();
    error AlreadySettled();
    error RedeemBeforeSettlement();
    error EthTransferFailed();

    event Split(address indexed user, address indexed receiver, uint256 amount);
    event Combined(address indexed user, address indexed receiver, uint256 amount);

    constructor(
        string memory ticker_,
        uint256 strike_,
        uint256 maturity_,
        address oracle_,
        string memory pName_,
        string memory pSymbol_,
        string memory nName_,
        string memory nSymbol_
    ) {
        if (strike_ == 0) revert ZeroStrike();
        if (maturity_ == 0) revert ZeroMaturity();
        if (oracle_ == address(0)) revert ZeroOracle();

        ticker = ticker_;
        strike = strike_;
        maturity = maturity_;
        oracle = IPriceOracle(oracle_);
        pToken = new ClaimToken(pName_, pSymbol_);
        nToken = new ClaimToken(nName_, nSymbol_);
    }

    function split(address receiver) external payable returns (uint256 amount) {
        if (msg.value == 0) revert ZeroAmount();
        if (block.timestamp >= maturity) revert SplitAfterMaturity();

        amount = msg.value;
        pToken.mint(receiver, amount);
        nToken.mint(receiver, amount);

        emit Split(msg.sender, receiver, amount);
    }

    function combine(uint256 amount, address receiver) external {
        if (settled) revert CombineAfterSettlement();
        if (amount == 0) revert ZeroAmount();

        pToken.burn(msg.sender, amount);
        nToken.burn(msg.sender, amount);
        _sendETH(receiver, amount);

        emit Combined(msg.sender, receiver, amount);
    }

    function _sendETH(address receiver, uint256 amount) internal {
        if (amount == 0) return;

        (bool ok, ) = receiver.call{ value: amount }("");
        if (!ok) revert EthTransferFailed();
    }
}
```

- [ ] **Step 4: Run split/combine tests and verify they pass**

Run:

```bash
forge test --match-contract OptionSeriesSplitCombineTest -vvv
```

Expected: PASS, 5 tests.

- [ ] **Step 5: Run ClaimToken tests again**

Run:

```bash
forge test --match-contract ClaimTokenTest -vvv
```

Expected: PASS, 3 tests.

- [ ] **Step 6: Commit split/combine implementation**

```bash
git add src/interfaces/IPriceOracle.sol src/OptionSeries.sol test/mocks/MockPriceOracle.sol test/OptionSeriesSplitCombine.t.sol
git commit -m "feat: add option series split and combine"
```

---

### Task 4: OptionSeries Settlement And Redemption

**Files:**
- Modify: `src/OptionSeries.sol`
- Create: `test/OptionSeriesSettlement.t.sol`

- [ ] **Step 1: Write failing settlement and redemption tests**

```solidity
// test/OptionSeriesSettlement.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ClaimToken } from "../src/ClaimToken.sol";
import { OptionSeries } from "../src/OptionSeries.sol";
import { MockPriceOracle } from "./mocks/MockPriceOracle.sol";
import { TestBase } from "./TestBase.sol";

contract OptionSeriesSettlementTest is TestBase {
    MockPriceOracle internal oracle;
    OptionSeries internal series;
    ClaimToken internal pToken;
    ClaimToken internal nToken;
    address internal alice = address(0xA11CE);
    uint256 internal maturity;

    function setUp() public {
        oracle = new MockPriceOracle();
        maturity = block.timestamp + 7 days;
        series = new OptionSeries(
            "USD/ETH",
            2000e18,
            maturity,
            address(oracle),
            "P USD/ETH 2000",
            "pUSD2000",
            "N USD/ETH 2000",
            "nUSD2000"
        );
        pToken = series.pToken();
        nToken = series.nToken();
        vm.deal(alice, 20 ether);
    }

    function testSettleRejectsBeforeMaturity() public {
        oracle.setResolvedValue(address(series), 2500e18);

        vm.expectRevert(OptionSeries.SettleBeforeMaturity.selector);
        series.settle();
    }

    function testSettleRejectsUnresolvedOracle() public {
        vm.warp(maturity);

        vm.expectRevert(OptionSeries.OracleUnresolved.selector);
        series.settle();
    }

    function testSettleRejectsZeroOracleValue() public {
        vm.warp(maturity);
        oracle.setResolvedValue(address(series), 0);

        vm.expectRevert(OptionSeries.InvalidOracleValue.selector);
        series.settle();
    }

    function testDuplicateSettlementRejected() public {
        _split(1 ether);
        vm.warp(maturity);
        oracle.setResolvedValue(address(series), 2500e18);
        series.settle();

        vm.expectRevert(OptionSeries.AlreadySettled.selector);
        series.settle();
    }

    function testSettlementBelowStrikeGivesAllCollateralToP() public {
        vm.warp(maturity);
        oracle.setResolvedValue(address(series), 1500e18);

        series.settle();

        assertTrue(series.settled(), "settled");
        assertEq(series.resolvedValue(), 1500e18, "resolved value");
        assertEq(series.payoutP(), 1e18, "P payout");
        assertEq(series.payoutN(), 0, "N payout");
    }

    function testSettlementAtStrikeGivesAllCollateralToP() public {
        vm.warp(maturity);
        oracle.setResolvedValue(address(series), 2000e18);

        series.settle();

        assertEq(series.payoutP(), 1e18, "P payout at strike");
        assertEq(series.payoutN(), 0, "N payout at strike");
    }

    function testSettlementAboveStrikeSplitsByStrikeOverResolvedValue() public {
        vm.warp(maturity);
        oracle.setResolvedValue(address(series), 2500e18);

        series.settle();

        assertEq(series.payoutP(), 800000000000000000, "P payout above strike");
        assertEq(series.payoutN(), 200000000000000000, "N payout above strike");
    }

    function testRedeemPAndNAfterSettlement() public {
        _split(10 ether);
        vm.warp(maturity);
        oracle.setResolvedValue(address(series), 2500e18);
        series.settle();

        uint256 balanceBeforeRedeem = alice.balance;

        vm.prank(alice);
        uint256 pPaid = series.redeemP(10 ether, alice);

        vm.prank(alice);
        uint256 nPaid = series.redeemN(10 ether, alice);

        assertEq(pPaid, 8 ether, "P paid");
        assertEq(nPaid, 2 ether, "N paid");
        assertEq(alice.balance, balanceBeforeRedeem + 10 ether, "alice receives all collateral");
        assertEq(address(series).balance, 0, "series drained");
        assertEq(pToken.totalSupply(), 0, "P supply after redemption");
        assertEq(nToken.totalSupply(), 0, "N supply after redemption");
    }

    function testRedeemRejectedBeforeSettlement() public {
        _split(1 ether);

        vm.expectRevert(OptionSeries.RedeemBeforeSettlement.selector);
        vm.prank(alice);
        series.redeemP(1 ether, alice);
    }

    function testCombineRejectedAfterSettlement() public {
        _split(1 ether);
        vm.warp(maturity);
        oracle.setResolvedValue(address(series), 2500e18);
        series.settle();

        vm.expectRevert(OptionSeries.CombineAfterSettlement.selector);
        vm.prank(alice);
        series.combine(1 ether, alice);
    }

    function testRedemptionDustIsBounded() public {
        _split(1);
        vm.warp(maturity);
        oracle.setResolvedValue(address(series), 3e18);
        series.settle();

        vm.prank(alice);
        series.redeemP(1, alice);

        vm.prank(alice);
        series.redeemN(1, alice);

        assertEq(pToken.totalSupply(), 0, "P supply after dust test");
        assertEq(nToken.totalSupply(), 0, "N supply after dust test");
        assertLe(address(series).balance, 1, "dust is bounded by one wei");
    }

    function _split(uint256 amount) internal {
        vm.prank(alice);
        series.split{ value: amount }(alice);
    }
}
```

- [ ] **Step 2: Run settlement tests and verify status**

Run:

```bash
forge test --match-contract OptionSeriesSettlementTest -vvv
```

Expected: FAIL because `settle`, `redeemP`, `redeemN`, `resolvedValue`, `payoutP`, and `payoutN` are not implemented yet.

- [ ] **Step 3: Ensure OptionSeries contains the final settlement and redemption implementation**

Replace `src/OptionSeries.sol` with this complete settlement-enabled implementation:

```solidity
// src/OptionSeries.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ClaimToken } from "./ClaimToken.sol";
import { IPriceOracle } from "./interfaces/IPriceOracle.sol";

contract OptionSeries {
    uint256 public constant ONE = 1e18;

    string public ticker;
    uint256 public immutable strike;
    uint256 public immutable maturity;
    IPriceOracle public immutable oracle;
    ClaimToken public immutable pToken;
    ClaimToken public immutable nToken;

    bool public settled;
    uint256 public resolvedValue;
    uint256 public payoutP;
    uint256 public payoutN;

    error ZeroStrike();
    error ZeroMaturity();
    error ZeroOracle();
    error ZeroAmount();
    error SplitAfterMaturity();
    error CombineAfterSettlement();
    error SettleBeforeMaturity();
    error OracleUnresolved();
    error InvalidOracleValue();
    error AlreadySettled();
    error RedeemBeforeSettlement();
    error EthTransferFailed();

    event Split(address indexed user, address indexed receiver, uint256 amount);
    event Combined(address indexed user, address indexed receiver, uint256 amount);
    event Settled(uint256 resolvedValue, uint256 payoutP, uint256 payoutN);
    event Redeemed(address indexed user, address indexed receiver, address indexed token, uint256 amount, uint256 ethPaid);

    constructor(
        string memory ticker_,
        uint256 strike_,
        uint256 maturity_,
        address oracle_,
        string memory pName_,
        string memory pSymbol_,
        string memory nName_,
        string memory nSymbol_
    ) {
        if (strike_ == 0) revert ZeroStrike();
        if (maturity_ == 0) revert ZeroMaturity();
        if (oracle_ == address(0)) revert ZeroOracle();

        ticker = ticker_;
        strike = strike_;
        maturity = maturity_;
        oracle = IPriceOracle(oracle_);
        pToken = new ClaimToken(pName_, pSymbol_);
        nToken = new ClaimToken(nName_, nSymbol_);
    }

    function split(address receiver) external payable returns (uint256 amount) {
        if (msg.value == 0) revert ZeroAmount();
        if (block.timestamp >= maturity) revert SplitAfterMaturity();

        amount = msg.value;
        pToken.mint(receiver, amount);
        nToken.mint(receiver, amount);

        emit Split(msg.sender, receiver, amount);
    }

    function combine(uint256 amount, address receiver) external {
        if (settled) revert CombineAfterSettlement();
        if (amount == 0) revert ZeroAmount();

        pToken.burn(msg.sender, amount);
        nToken.burn(msg.sender, amount);
        _sendETH(receiver, amount);

        emit Combined(msg.sender, receiver, amount);
    }

    function settle() external {
        if (settled) revert AlreadySettled();
        if (block.timestamp < maturity) revert SettleBeforeMaturity();

        (bool isResolved, uint256 x) = oracle.getResolvedValue(address(this));
        if (!isResolved) revert OracleUnresolved();
        if (x == 0) revert InvalidOracleValue();

        uint256 p = strike >= x ? ONE : (strike * ONE) / x;

        resolvedValue = x;
        payoutP = p;
        payoutN = ONE - p;
        settled = true;

        emit Settled(x, payoutP, payoutN);
    }

    function redeemP(uint256 amount, address receiver) external returns (uint256 ethPaid) {
        return _redeem(pToken, payoutP, amount, receiver);
    }

    function redeemN(uint256 amount, address receiver) external returns (uint256 ethPaid) {
        return _redeem(nToken, payoutN, amount, receiver);
    }

    function _redeem(ClaimToken token, uint256 payout, uint256 amount, address receiver) internal returns (uint256 ethPaid) {
        if (!settled) revert RedeemBeforeSettlement();
        if (amount == 0) revert ZeroAmount();

        token.burn(msg.sender, amount);
        ethPaid = (amount * payout) / ONE;
        _sendETH(receiver, ethPaid);

        emit Redeemed(msg.sender, receiver, address(token), amount, ethPaid);
    }

    function _sendETH(address receiver, uint256 amount) internal {
        if (amount == 0) return;

        (bool ok, ) = receiver.call{ value: amount }("");
        if (!ok) revert EthTransferFailed();
    }
}
```

- [ ] **Step 4: Run all OptionSeries tests**

Run:

```bash
forge test --match-contract OptionSeries -vvv
```

Expected: PASS for `OptionSeriesSplitCombineTest` and `OptionSeriesSettlementTest`.

- [ ] **Step 5: Commit settlement and redemption tests**

```bash
git add src/OptionSeries.sol test/OptionSeriesSettlement.t.sol
git commit -m "feat: add option settlement and redemption"
```

---

### Task 5: OptionFactory

**Files:**
- Create: `src/OptionFactory.sol`
- Create: `test/OptionFactory.t.sol`

- [ ] **Step 1: Write failing factory tests**

```solidity
// test/OptionFactory.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { OptionFactory } from "../src/OptionFactory.sol";
import { OptionSeries } from "../src/OptionSeries.sol";
import { MockPriceOracle } from "./mocks/MockPriceOracle.sol";
import { TestBase } from "./TestBase.sol";

contract OptionFactoryTest is TestBase {
    event OptionSeriesCreated(
        address indexed series,
        string ticker,
        uint256 strike,
        uint256 maturity,
        address oracle,
        address pToken,
        address nToken
    );

    OptionFactory internal factory;
    MockPriceOracle internal oracle;
    uint256 internal maturity;

    function setUp() public {
        factory = new OptionFactory();
        oracle = new MockPriceOracle();
        maturity = block.timestamp + 30 days;
    }

    function testCreateSeriesDeploysConfiguredMarket() public {
        vm.expectEmit(false, false, false, false);
        emit OptionSeriesCreated(address(0), "", 0, 0, address(0), address(0), address(0));

        address seriesAddress = factory.createSeries(
            "USD/ETH",
            2000e18,
            maturity,
            address(oracle),
            "P USD/ETH 2000",
            "pUSD2000",
            "N USD/ETH 2000",
            "nUSD2000"
        );

        OptionSeries series = OptionSeries(seriesAddress);

        assertStrEq(series.ticker(), "USD/ETH", "ticker");
        assertEq(series.strike(), 2000e18, "strike");
        assertEq(series.maturity(), maturity, "maturity");
        assertEq(address(series.oracle()), address(oracle), "oracle");
        assertStrEq(series.pToken().name(), "P USD/ETH 2000", "P name");
        assertStrEq(series.pToken().symbol(), "pUSD2000", "P symbol");
        assertStrEq(series.nToken().name(), "N USD/ETH 2000", "N name");
        assertStrEq(series.nToken().symbol(), "nUSD2000", "N symbol");
    }

    function testCreateSeriesRejectsZeroStrike() public {
        vm.expectRevert(OptionSeries.ZeroStrike.selector);
        factory.createSeries(
            "USD/ETH",
            0,
            maturity,
            address(oracle),
            "P USD/ETH 2000",
            "pUSD2000",
            "N USD/ETH 2000",
            "nUSD2000"
        );
    }

    function testCreateSeriesRejectsZeroMaturity() public {
        vm.expectRevert(OptionSeries.ZeroMaturity.selector);
        factory.createSeries(
            "USD/ETH",
            2000e18,
            0,
            address(oracle),
            "P USD/ETH 2000",
            "pUSD2000",
            "N USD/ETH 2000",
            "nUSD2000"
        );
    }

    function testCreateSeriesRejectsZeroOracle() public {
        vm.expectRevert(OptionSeries.ZeroOracle.selector);
        factory.createSeries(
            "USD/ETH",
            2000e18,
            maturity,
            address(0),
            "P USD/ETH 2000",
            "pUSD2000",
            "N USD/ETH 2000",
            "nUSD2000"
        );
    }
}
```

- [ ] **Step 2: Run factory tests and verify they fail**

Run:

```bash
forge test --match-contract OptionFactoryTest -vvv
```

Expected: FAIL because `src/OptionFactory.sol` does not exist.

- [ ] **Step 3: Implement OptionFactory**

```solidity
// src/OptionFactory.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { OptionSeries } from "./OptionSeries.sol";

contract OptionFactory {
    event OptionSeriesCreated(
        address indexed series,
        string ticker,
        uint256 strike,
        uint256 maturity,
        address oracle,
        address pToken,
        address nToken
    );

    function createSeries(
        string memory ticker,
        uint256 strike,
        uint256 maturity,
        address oracle,
        string memory pName,
        string memory pSymbol,
        string memory nName,
        string memory nSymbol
    ) external returns (address seriesAddress) {
        OptionSeries series = new OptionSeries(ticker, strike, maturity, oracle, pName, pSymbol, nName, nSymbol);
        seriesAddress = address(series);

        emit OptionSeriesCreated(
            seriesAddress,
            ticker,
            strike,
            maturity,
            oracle,
            address(series.pToken()),
            address(series.nToken())
        );
    }
}
```

- [ ] **Step 4: Run factory tests and verify they pass**

Run:

```bash
forge test --match-contract OptionFactoryTest -vvv
```

Expected: PASS, 4 tests.

- [ ] **Step 5: Commit factory**

```bash
git add src/OptionFactory.sol test/OptionFactory.t.sol
git commit -m "feat: add option series factory"
```

---

### Task 6: Full Verification And Cleanup

**Files:**
- Modify only files touched by prior tasks if verification exposes a concrete failure.

- [ ] **Step 1: Run the full test suite**

Run:

```bash
forge test -vvv
```

Expected: PASS for all contracts:

- `ClaimTokenTest`: 3 tests.
- `OptionSeriesSplitCombineTest`: 5 tests.
- `OptionSeriesSettlementTest`: 11 tests.
- `OptionFactoryTest`: 4 tests.

- [ ] **Step 2: Run formatting**

Run:

```bash
forge fmt
```

Expected: command exits successfully and formats Solidity files in place.

- [ ] **Step 3: Run diff hygiene checks**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 4: Run full tests after formatting**

Run:

```bash
forge test -vvv
```

Expected: PASS for all 23 tests.

- [ ] **Step 5: Inspect final git status**

Run:

```bash
git status --short
```

Expected: only intentional files are modified or untracked.

- [ ] **Step 6: Commit verification cleanup if formatting changed files**

If `forge fmt` changed tracked files, run:

```bash
git add src test foundry.toml .gitignore
git commit -m "chore: format option prototype"
```

If `forge fmt` changed nothing, do not create an empty commit.

---

## Self-Review Notes

Spec coverage:

- Fresh Foundry project: Task 1.
- Core option series factory: Task 5.
- One option series contract per market: Tasks 3 and 5.
- One ERC20 P token and one ERC20 N token per option series: Tasks 2 and 3.
- Oracle abstraction through an interface: Task 3.
- Mock oracle implementation for tests: Task 3.
- Lifecycle tests for split, combine, maturity, settlement, redemption, and dust: Tasks 3 and 4.
- No wrapper, rebalancer, AMM, production oracle, or dispute flow appears in the implementation tasks.

Type consistency:

- `OptionSeries.pToken()` and `OptionSeries.nToken()` return `ClaimToken`.
- `IPriceOracle.getResolvedValue(address)` matches `MockPriceOracle`.
- `OptionFactory.createSeries(...)` forwards the same constructor arguments used by `OptionSeries`.
- Custom error selectors used in tests are defined on `OptionSeries` or `ClaimToken`.

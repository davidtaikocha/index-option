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

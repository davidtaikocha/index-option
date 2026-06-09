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

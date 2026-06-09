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

    // settle < 0 liquidation: loss exceeds margin -> gross 0 -> keeper unrewarded,
    // insurance draws to make the vault whole; position is cleared without revert.
    function testBadDebtLiquidationDrawsInsuranceKeeperUnrewarded() public {
        // 20x long: margin 1, notional 20, units 40e18, entry 0.5
        vm.prank(trader);
        uint256 id = perp.open{value: 1 ether}(true, 20e18, type(uint256).max);
        uint256 insBefore = address(insurance).balance;
        uint256 keeperBefore = liquidator.balance;
        // crash to level 0.3333 -> pnl ~ -6.67 ETH, far beyond 1 ETH margin -> settle < 0
        _push(3000e18);
        vm.prank(liquidator);
        uint256 charged = perp.liquidate(id);
        assertEq(charged, 0, "no penalty charged when wiped out");
        assertEq(liquidator.balance, keeperBefore, "keeper unrewarded on bad debt");
        assertTrue(address(insurance).balance < insBefore, "insurance covered shortfall");
        (address o,,,,,,,) = perp.positions(id);
        assertEq(o, address(0), "position cleared");
        assertEq(vault.reserved(), 0, "reserve released");
    }

    // Short-side liquidation: level rises so the short loses beyond maintenance.
    function testUnderwaterShortIsLiquidated() public {
        // 10x short: margin 1, notional 10, units 20e18, entry 0.5
        vm.prank(trader);
        uint256 id = perp.open{value: 1 ether}(false, 10e18, 0);
        // raise level: x=4400 -> level 0.5454 -> short pnl = 20e18*(0.5-0.5454) ~ -0.909 ETH
        // equity ~ 0.0909 (0 < equity < mm 0.5) so a penalty is actually charged
        _push(4400e18);
        uint256 keeperBefore = liquidator.balance;
        vm.prank(liquidator);
        uint256 charged = perp.liquidate(id);
        assertTrue(charged > 0, "penalty charged");
        assertTrue(liquidator.balance > keeperBefore, "keeper rewarded");
        (address o,,,,,,,) = perp.positions(id);
        assertEq(o, address(0), "short position cleared");
        assertEq(vault.reserved(), 0, "reserve released");
    }
}

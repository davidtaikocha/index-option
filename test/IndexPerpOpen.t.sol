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

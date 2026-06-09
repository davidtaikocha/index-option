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

    // settle < 0 branch: loss exceeds margin -> trader gets 0, margin goes to vault,
    // insurance covers the shortfall, position is deleted.
    function testLongWipeoutDrawsInsurance() public {
        // 20x long: margin ~1 ETH, notional 20, units 40e18, entry level 0.5
        vm.prank(trader);
        uint256 id = perp.open{value: 1 ether}(true, 20e18, type(uint256).max);
        uint256 vaultBefore = vault.totalAssets();
        uint256 insBefore = address(insurance).balance;
        uint256 traderBefore = trader.balance;
        // level 0.3333 -> pnl ~ -6.67 ETH, far exceeding 1 ETH margin -> settle < 0
        _push(3000e18);
        vm.prank(trader);
        perp.close(id, 0);
        // trader receives nothing
        assertEq(trader.balance, traderBefore, "trader gets 0 on wipeout");
        // position deleted
        (address o,,,,,,,) = perp.positions(id);
        assertEq(o, address(0), "position deleted");
        // vault received margin (takeLoss) plus the insurance-covered shortfall
        assertTrue(vault.totalAssets() > vaultBefore + 1 ether, "vault got margin + shortfall");
        // insurance was drained to cover the shortfall
        assertTrue(address(insurance).balance < insBefore, "insurance covered shortfall");
    }
}

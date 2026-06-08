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

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
        uint256 ts = pool.totalShares(); // cache before prank so the view call doesn't consume it
        vm.prank(lp);
        (uint256 outP, uint256 outN) = pool.withdraw(ts);
        assertEq(outP, rp, "reclaims all P reserves");
        assertEq(outN, rn, "reclaims all N reserves");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ClaimToken} from "../src/ClaimToken.sol";
import {OptionSeries} from "../src/OptionSeries.sol";
import {MockPriceOracle} from "./mocks/MockPriceOracle.sol";
import {UUPSTestBase} from "./UUPSTestBase.sol";

contract OptionSeriesSplitCombineTest is UUPSTestBase {
    MockPriceOracle internal oracle;
    OptionSeries internal series;
    ClaimToken internal pToken;
    ClaimToken internal nToken;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    uint256 internal maturity;

    function setUp() public {
        oracle = new MockPriceOracle();
        maturity = block.timestamp + 7 days;
        series = _deploySeriesProxy(2000e18, maturity, address(oracle));
        pToken = series.pToken();
        nToken = series.nToken();
        vm.deal(alice, 10 ether);
    }

    function testSplitMintsEqualClaimsAndStoresCollateral() public {
        vm.prank(alice);
        series.split{value: 2 ether}(alice);

        assertEq(address(series).balance, 2 ether, "series collateral");
        assertEq(pToken.balanceOf(alice), 2 ether, "alice P balance");
        assertEq(nToken.balanceOf(alice), 2 ether, "alice N balance");
        assertEq(pToken.totalSupply(), 2 ether, "P supply");
        assertEq(nToken.totalSupply(), 2 ether, "N supply");
    }

    function testSeriesUsesFixedEthUsdcTokenMetadata() public view {
        assertStrEq(pToken.name(), "Protected ETH/USDC", "P token name");
        assertStrEq(pToken.symbol(), "pETHUSDC", "P token symbol");
        assertStrEq(nToken.name(), "Complement ETH/USDC", "N token name");
        assertStrEq(nToken.symbol(), "nETHUSDC", "N token symbol");
    }

    function testCombineBurnsClaimsAndReturnsEthBeforeMaturity() public {
        vm.prank(alice);
        series.split{value: 2 ether}(alice);

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

    function testCombineRejectsZeroReceiverBeforeBurningClaims() public {
        vm.prank(alice);
        series.split{value: 2 ether}(alice);

        vm.expectRevert(OptionSeries.InvalidRecipient.selector);
        vm.prank(alice);
        series.combine(1 ether, address(0));

        assertEq(address(series).balance, 2 ether, "series collateral unchanged");
        assertEq(pToken.balanceOf(alice), 2 ether, "alice P unchanged");
        assertEq(nToken.balanceOf(alice), 2 ether, "alice N unchanged");
        assertEq(pToken.totalSupply(), 2 ether, "P supply unchanged");
        assertEq(nToken.totalSupply(), 2 ether, "N supply unchanged");
    }

    function testCombineChecksZeroReceiverBeforePBalance() public {
        vm.expectRevert(OptionSeries.InvalidRecipient.selector);
        vm.prank(bob);
        series.combine(1 ether, address(0));
    }

    function testSplitRejectsZeroAmount() public {
        vm.expectRevert(OptionSeries.ZeroAmount.selector);
        vm.prank(alice);
        series.split{value: 0}(alice);
    }

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

    function testCombineAllowedAfterMaturityBeforeSettlement() public {
        vm.prank(alice);
        series.split{value: 1 ether}(alice);

        vm.warp(maturity);
        uint256 balanceBeforeCombine = alice.balance;

        vm.prank(alice);
        series.combine(1 ether, alice);

        assertEq(alice.balance, balanceBeforeCombine + 1 ether, "alice receives ETH after maturity");
        assertEq(address(series).balance, 0, "series collateral after combine");
    }
}

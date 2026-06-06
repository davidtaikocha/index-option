// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ClaimToken} from "../src/ClaimToken.sol";
import {OptionSeries} from "../src/OptionSeries.sol";
import {MockPriceOracle} from "./mocks/MockPriceOracle.sol";
import {TestBase} from "./TestBase.sol";

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
            "USD/ETH", 2000e18, maturity, address(oracle), "P USD/ETH 2000", "pUSD2000", "N USD/ETH 2000", "nUSD2000"
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

    function testConstructorRejectsStrikeThatCanOverflowSettlementMath() public {
        vm.expectRevert(OptionSeries.StrikeTooLarge.selector);
        new OptionSeries(
            "USD/ETH",
            type(uint256).max / 1e18 + 1,
            maturity,
            address(oracle),
            "P USD/ETH overflow",
            "pUSDOverflow",
            "N USD/ETH overflow",
            "nUSDOverflow"
        );
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

    function testRedeemRejectsZeroAmountAfterSettlement() public {
        _split(1 ether);
        vm.warp(maturity);
        oracle.setResolvedValue(address(series), 2500e18);
        series.settle();

        vm.expectRevert(OptionSeries.ZeroAmount.selector);
        vm.prank(alice);
        series.redeemP(0, alice);
    }

    function testRedeemPRejectsZeroReceiverBeforeBurningNonzeroPayoutLeg() public {
        _split(1 ether);
        vm.warp(maturity);
        oracle.setResolvedValue(address(series), 2500e18);
        series.settle();

        vm.expectRevert(OptionSeries.InvalidRecipient.selector);
        vm.prank(alice);
        series.redeemP(1 ether, address(0));

        assertEq(address(series).balance, 1 ether, "series collateral unchanged");
        assertEq(pToken.balanceOf(alice), 1 ether, "alice P unchanged");
        assertEq(pToken.totalSupply(), 1 ether, "P supply unchanged");
    }

    function testRedeemNRejectsZeroReceiverBeforeBurningZeroPayoutLeg() public {
        _split(1 ether);
        vm.warp(maturity);
        oracle.setResolvedValue(address(series), 2000e18);
        series.settle();

        vm.expectRevert(OptionSeries.InvalidRecipient.selector);
        vm.prank(alice);
        series.redeemN(1 ether, address(0));

        assertEq(address(series).balance, 1 ether, "series collateral unchanged");
        assertEq(nToken.balanceOf(alice), 1 ether, "alice N unchanged");
        assertEq(nToken.totalSupply(), 1 ether, "N supply unchanged");
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

    function testFragmentedRedemptionDustIsGloballyBounded() public {
        _split(3);
        vm.warp(maturity);
        oracle.setResolvedValue(address(series), 4000e18);
        series.settle();

        for (uint256 i; i < 3; i++) {
            vm.prank(alice);
            series.redeemP(1, alice);

            vm.prank(alice);
            series.redeemN(1, alice);
        }

        assertEq(pToken.totalSupply(), 0, "P supply after fragmented redemption");
        assertEq(nToken.totalSupply(), 0, "N supply after fragmented redemption");
        assertLe(address(series).balance, 1, "fragmented dust is globally bounded");
    }

    function _split(uint256 amount) internal {
        vm.prank(alice);
        series.split{value: amount}(alice);
    }
}

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

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OptionFactory} from "../src/OptionFactory.sol";
import {OptionSeries} from "../src/OptionSeries.sol";
import {MockPriceOracle} from "./mocks/MockPriceOracle.sol";
import {TestBase, Vm} from "./TestBase.sol";

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
        vm.recordLogs();
        address seriesAddress = factory.createSeries(
            "USD/ETH", 2000e18, maturity, address(oracle), "P USD/ETH 2000", "pUSD2000", "N USD/ETH 2000", "nUSD2000"
        );

        OptionSeries series = OptionSeries(seriesAddress);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "event count");
        assertEq(logs[0].emitter, address(factory), "event emitter");
        assertEq(logs[0].topics.length, 2, "event topic count");
        assertEq(
            logs[0].topics[0],
            keccak256("OptionSeriesCreated(address,string,uint256,uint256,address,address,address)"),
            "event signature"
        );
        assertEq(address(uint160(uint256(logs[0].topics[1]))), seriesAddress, "event series topic");

        (
            string memory eventTicker,
            uint256 eventStrike,
            uint256 eventMaturity,
            address eventOracle,
            address eventPToken,
            address eventNToken
        ) = abi.decode(logs[0].data, (string, uint256, uint256, address, address, address));

        assertStrEq(series.ticker(), "USD/ETH", "ticker");
        assertEq(series.strike(), 2000e18, "strike");
        assertEq(series.maturity(), maturity, "maturity");
        assertEq(address(series.oracle()), address(oracle), "oracle");
        assertStrEq(series.pToken().name(), "P USD/ETH 2000", "P name");
        assertStrEq(series.pToken().symbol(), "pUSD2000", "P symbol");
        assertStrEq(series.nToken().name(), "N USD/ETH 2000", "N name");
        assertStrEq(series.nToken().symbol(), "nUSD2000", "N symbol");
        assertStrEq(eventTicker, series.ticker(), "event ticker");
        assertEq(eventStrike, series.strike(), "event strike");
        assertEq(eventMaturity, series.maturity(), "event maturity");
        assertEq(eventOracle, address(series.oracle()), "event oracle");
        assertEq(eventPToken, address(series.pToken()), "event P token");
        assertEq(eventNToken, address(series.nToken()), "event N token");
    }

    function testCreateSeriesRejectsZeroStrike() public {
        vm.expectRevert(OptionSeries.ZeroStrike.selector);
        factory.createSeries(
            "USD/ETH", 0, maturity, address(oracle), "P USD/ETH 2000", "pUSD2000", "N USD/ETH 2000", "nUSD2000"
        );
    }

    function testCreateSeriesRejectsZeroMaturity() public {
        vm.expectRevert(OptionSeries.ZeroMaturity.selector);
        factory.createSeries(
            "USD/ETH", 2000e18, 0, address(oracle), "P USD/ETH 2000", "pUSD2000", "N USD/ETH 2000", "nUSD2000"
        );
    }

    function testCreateSeriesRejectsStrikeTooLarge() public {
        OptionSeries referenceSeries = new OptionSeries(
            "USD/ETH", 2000e18, maturity, address(oracle), "P USD/ETH 2000", "pUSD2000", "N USD/ETH 2000", "nUSD2000"
        );
        uint256 strikeTooLarge = type(uint256).max / referenceSeries.ONE() + 1;

        vm.expectRevert(OptionSeries.StrikeTooLarge.selector);
        factory.createSeries(
            "USD/ETH",
            strikeTooLarge,
            maturity,
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
            "USD/ETH", 2000e18, maturity, address(0), "P USD/ETH 2000", "pUSD2000", "N USD/ETH 2000", "nUSD2000"
        );
    }
}

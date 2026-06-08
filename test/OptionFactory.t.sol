// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OptionFactory} from "../src/OptionFactory.sol";
import {OptionSeries} from "../src/OptionSeries.sol";
import {MockPriceOracle} from "./mocks/MockPriceOracle.sol";
import {TestBase, Vm} from "./TestBase.sol";

contract OptionFactoryTest is TestBase {
    event OptionSeriesCreated(
        address indexed series, uint256 strike, uint256 maturity, address oracle, address pToken, address nToken
    );

    OptionFactory internal factory;
    MockPriceOracle internal oracle;
    uint256 internal maturity;

    function setUp() public {
        factory = new OptionFactory();
        oracle = new MockPriceOracle();
        maturity = block.timestamp + 30 days;
    }

    function testCreateSeriesDeploysConfiguredEthUsdcMarket() public {
        vm.recordLogs();
        address seriesAddress = factory.createSeries(2000e18, maturity, address(oracle));

        OptionSeries series = OptionSeries(seriesAddress);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        Vm.Log memory seriesCreatedLog;
        bool foundSeriesCreatedLog;

        for (uint256 i; i < logs.length; i++) {
            if (
                logs[i].emitter == address(factory) && logs[i].topics.length > 0
                    && logs[i].topics[0] == OptionSeriesCreated.selector
            ) {
                seriesCreatedLog = logs[i];
                foundSeriesCreatedLog = true;
                break;
            }
        }

        assertTrue(foundSeriesCreatedLog, "series created event");
        assertEq(seriesCreatedLog.topics.length, 2, "event topic count");
        assertEq(address(uint160(uint256(seriesCreatedLog.topics[1]))), seriesAddress, "event series topic");

        (uint256 eventStrike, uint256 eventMaturity, address eventOracle, address eventPToken, address eventNToken) =
            abi.decode(seriesCreatedLog.data, (uint256, uint256, address, address, address));

        assertEq(series.strike(), 2000e18, "strike");
        assertEq(series.maturity(), maturity, "maturity");
        assertEq(address(series.oracle()), address(oracle), "oracle");
        assertStrEq(series.pToken().name(), "Protected ETH/USDC", "P name");
        assertStrEq(series.pToken().symbol(), "pETHUSDC", "P symbol");
        assertStrEq(series.nToken().name(), "Complement ETH/USDC", "N name");
        assertStrEq(series.nToken().symbol(), "nETHUSDC", "N symbol");
        assertEq(eventStrike, series.strike(), "event strike");
        assertEq(eventMaturity, series.maturity(), "event maturity");
        assertEq(eventOracle, address(series.oracle()), "event oracle");
        assertEq(eventPToken, address(series.pToken()), "event P token");
        assertEq(eventNToken, address(series.nToken()), "event N token");
    }

    function testCreateSeriesRejectsZeroStrike() public {
        vm.expectRevert(OptionSeries.ZeroStrike.selector);
        factory.createSeries(0, maturity, address(oracle));
    }

    function testCreateSeriesRejectsZeroMaturity() public {
        vm.expectRevert(OptionSeries.ZeroMaturity.selector);
        factory.createSeries(2000e18, 0, address(oracle));
    }

    function testCreateSeriesRejectsStrikeTooLarge() public {
        OptionSeries referenceSeries = new OptionSeries(2000e18, maturity, address(oracle));
        uint256 strikeTooLarge = type(uint256).max / referenceSeries.ONE() + 1;

        vm.expectRevert(OptionSeries.StrikeTooLarge.selector);
        factory.createSeries(strikeTooLarge, maturity, address(oracle));
    }

    function testCreateSeriesRejectsZeroOracle() public {
        vm.expectRevert(OptionSeries.ZeroOracle.selector);
        factory.createSeries(2000e18, maturity, address(0));
    }
}

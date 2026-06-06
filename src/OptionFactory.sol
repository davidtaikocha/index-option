// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { OptionSeries } from "./OptionSeries.sol";

contract OptionFactory {
    event OptionSeriesCreated(
        address indexed series,
        string ticker,
        uint256 strike,
        uint256 maturity,
        address oracle,
        address pToken,
        address nToken
    );

    function createSeries(
        string memory ticker,
        uint256 strike,
        uint256 maturity,
        address oracle,
        string memory pName,
        string memory pSymbol,
        string memory nName,
        string memory nSymbol
    )
        external
        returns (address seriesAddress)
    {
        OptionSeries series = new OptionSeries(ticker, strike, maturity, oracle, pName, pSymbol, nName, nSymbol);
        seriesAddress = address(series);

        emit OptionSeriesCreated(
            seriesAddress,
            ticker,
            strike,
            maturity,
            oracle,
            address(series.pToken()),
            address(series.nToken())
        );
    }
}

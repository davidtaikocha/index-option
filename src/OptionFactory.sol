// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OptionSeries} from "./OptionSeries.sol";

/// @title OptionFactory
/// @notice Deploys self-contained option series contracts.
/// @dev The factory is intentionally stateless. Each deployed `OptionSeries`
///      owns its own ETH collateral and P/N claim tokens, so no global factory
///      accounting is required.
contract OptionFactory {
    /// @notice Emitted after a new option series and its P/N tokens are deployed.
    /// @param series Address of the newly deployed option series.
    /// @param ticker Human-readable ticker label for the resolved index.
    /// @param strike 1e18 fixed-point strike value denominated in ETH terms.
    /// @param maturity Timestamp after which the series can be settled.
    /// @param oracle Oracle contract used by the series at settlement.
    /// @param pToken P-side claim token deployed by the series.
    /// @param nToken N-side claim token deployed by the series.
    event OptionSeriesCreated(
        address indexed series,
        string ticker,
        uint256 strike,
        uint256 maturity,
        address oracle,
        address pToken,
        address nToken
    );

    /// @notice Deploys a new option series and returns its address.
    /// @dev Constructor validation is delegated to `OptionSeries`; validation
    ///      errors such as zero strike or zero oracle propagate unchanged.
    /// @param ticker Human-readable ticker label for the resolved index.
    /// @param strike 1e18 fixed-point strike value denominated in ETH terms.
    /// @param maturity Timestamp after which settlement is allowed.
    /// @param oracle Oracle contract implementing `IPriceOracle`.
    /// @param pName ERC20-style name for the P claim token.
    /// @param pSymbol ERC20-style symbol for the P claim token.
    /// @param nName ERC20-style name for the N claim token.
    /// @param nSymbol ERC20-style symbol for the N claim token.
    /// @return seriesAddress Address of the newly deployed option series.
    function createSeries(
        string memory ticker,
        uint256 strike,
        uint256 maturity,
        address oracle,
        string memory pName,
        string memory pSymbol,
        string memory nName,
        string memory nSymbol
    ) external returns (address seriesAddress) {
        OptionSeries series = new OptionSeries(ticker, strike, maturity, oracle, pName, pSymbol, nName, nSymbol);
        seriesAddress = address(series);

        emit OptionSeriesCreated(
            seriesAddress, ticker, strike, maturity, oracle, address(series.pToken()), address(series.nToken())
        );
    }
}

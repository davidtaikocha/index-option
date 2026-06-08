// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OptionSeries} from "./OptionSeries.sol";

/// @title OptionFactory
/// @notice Deploys self-contained ETH/USDC option series contracts.
/// @dev The factory is intentionally stateless. Each deployed `OptionSeries`
///      owns its own ETH collateral and P/N claim tokens, so no global factory
///      accounting is required.
contract OptionFactory {
    /// @notice Emitted after a new ETH/USDC option series and its P/N tokens are deployed.
    /// @param series Address of the newly deployed option series.
    /// @param strike 1e18 fixed-point ETH/USDC strike price.
    /// @param maturity Timestamp after which the series can be settled.
    /// @param oracle Oracle contract used by the series at settlement.
    /// @param pToken P-side claim token deployed by the series.
    /// @param nToken N-side claim token deployed by the series.
    event OptionSeriesCreated(
        address indexed series, uint256 strike, uint256 maturity, address oracle, address pToken, address nToken
    );

    /// @notice Deploys a new ETH/USDC option series and returns its address.
    /// @dev Constructor validation is delegated to `OptionSeries`; validation
    ///      errors such as zero strike or zero oracle propagate unchanged.
    /// @param strike 1e18 fixed-point ETH/USDC strike price.
    /// @param maturity Timestamp after which settlement is allowed.
    /// @param oracle Oracle contract implementing `IPriceOracle`.
    /// @return seriesAddress Address of the newly deployed option series.
    function createSeries(uint256 strike, uint256 maturity, address oracle) external returns (address seriesAddress) {
        OptionSeries series = new OptionSeries(strike, maturity, oracle);
        seriesAddress = address(series);

        emit OptionSeriesCreated(
            seriesAddress, strike, maturity, oracle, address(series.pToken()), address(series.nToken())
        );
    }
}

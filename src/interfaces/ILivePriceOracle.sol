// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ILivePriceOracle
/// @notice Live (non-resolved) ETH/USDC spot feed for perps and index marking.
interface ILivePriceOracle {
    /// @param feedId Identifier of the price feed.
    /// @return value 1e18 USDC per ETH. Zero means unset.
    /// @return updatedAt Timestamp of the last push. Consumers enforce staleness.
    function getSpotValue(bytes32 feedId) external view returns (uint256 value, uint256 updatedAt);
}

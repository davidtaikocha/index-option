// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IPriceOracle
/// @notice Oracle boundary used by an ETH/USDC option series at maturity.
/// @dev The option contracts only require a resolved/non-resolved flag plus a
///      1e18 fixed-point ETH/USDC price. Dispute, escalation, and data-source
///      logic intentionally live outside this interface.
interface IPriceOracle {
    /// @notice Returns the maturity ETH/USDC price for an option series, if resolved.
    /// @param series Option series requesting its resolved ETH/USDC price.
    /// @return resolved Whether the oracle has finalized a value for `series`.
    /// @return value The resolved 1e18 fixed-point ETH/USDC price. Zero is invalid.
    function getResolvedValue(address series) external view returns (bool resolved, uint256 value);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPriceOracle} from "../../src/interfaces/IPriceOracle.sol";

/// @title MockPriceOracle
/// @notice Test-only oracle that stores resolved values by option series address.
/// @dev This mock intentionally has no access control so tests can freely set,
///      clear, and overwrite oracle state for each scenario.
contract MockPriceOracle is IPriceOracle {
    /// @notice Resolution state for one option series.
    struct Resolution {
        /// @notice Whether the series has been resolved.
        bool resolved;
        /// @notice Resolved 1e18 fixed-point ticker value.
        uint256 value;
    }

    /// @notice Stored resolution data by series address.
    mapping(address series => Resolution resolution) internal resolutions;

    /// @notice Marks `series` resolved with `value`.
    function setResolvedValue(address series, uint256 value) external {
        resolutions[series] = Resolution({resolved: true, value: value});
    }

    /// @notice Clears the stored resolution for `series`.
    function clearResolvedValue(address series) external {
        delete resolutions[series];
    }

    /// @inheritdoc IPriceOracle
    function getResolvedValue(address series) external view returns (bool resolved, uint256 value) {
        Resolution storage resolution = resolutions[series];
        return (resolution.resolved, resolution.value);
    }
}

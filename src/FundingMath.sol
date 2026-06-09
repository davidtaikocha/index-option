// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title FundingMath
/// @notice Pure accrual math for the perpetual borrow fee and skew funding.
/// @dev All rates are per-second, scaled by 1e18. Accumulators integrate these
///      deltas over time; positions settle the delta since their entry snapshot.
library FundingMath {
    uint256 internal constant ONE = 1e18;

    /// @notice Borrow accumulator increment over `dt` seconds (>= 0).
    /// @return ETH owed per ETH of notional, scaled 1e18.
    function borrowDelta(uint256 borrowBase, uint256 reserved, uint256 vaultAssets, uint256 dt)
        internal
        pure
        returns (uint256)
    {
        if (vaultAssets == 0 || dt == 0) return 0;
        uint256 util = reserved >= vaultAssets ? ONE : (reserved * ONE) / vaultAssets;
        return ((borrowBase * util) / ONE) * dt;
    }

    /// @notice Signed funding accumulator increment over `dt` seconds.
    /// @dev Positive => longs pay shorts (open interest is long-heavy).
    function fundingDelta(uint256 fundK, uint256 longOI, uint256 shortOI, uint256 dt)
        internal
        pure
        returns (int256)
    {
        uint256 totalOI = longOI + shortOI;
        if (totalOI == 0 || dt == 0) return 0;
        int256 skew = ((int256(longOI) - int256(shortOI)) * int256(ONE)) / int256(totalOI);
        return ((int256(fundK) * skew) / int256(ONE)) * int256(dt);
    }
}

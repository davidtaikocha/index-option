// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPriceOracle {
    function getResolvedValue(address series) external view returns (bool resolved, uint256 value);
}

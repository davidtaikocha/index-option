// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IPriceOracle } from "../../src/interfaces/IPriceOracle.sol";

contract MockPriceOracle is IPriceOracle {
    struct Resolution {
        bool resolved;
        uint256 value;
    }

    mapping(address series => Resolution resolution) internal resolutions;

    function setResolvedValue(address series, uint256 value) external {
        resolutions[series] = Resolution({ resolved: true, value: value });
    }

    function clearResolvedValue(address series) external {
        delete resolutions[series];
    }

    function getResolvedValue(address series) external view returns (bool resolved, uint256 value) {
        Resolution storage resolution = resolutions[series];
        return (resolution.resolved, resolution.value);
    }
}

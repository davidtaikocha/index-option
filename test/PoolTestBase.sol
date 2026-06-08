// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ClaimToken} from "../src/ClaimToken.sol";
import {OptionSeries} from "../src/OptionSeries.sol";
import {OptionPool} from "../src/OptionPool.sol";
import {MockPriceOracle} from "./mocks/MockPriceOracle.sol";
import {UUPSTestBase} from "./UUPSTestBase.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @notice Shared setup for OptionPool tests: a settled-capable series plus a pool proxy.
contract PoolTestBase is UUPSTestBase {
    MockPriceOracle internal oracle;
    OptionSeries internal series;
    ClaimToken internal pToken;
    ClaimToken internal nToken;
    OptionPool internal pool;
    uint256 internal maturity;

    address internal lp = address(0x11D);
    address internal trader = address(0x7AD);

    function _deployPoolProxy(address series_) internal returns (OptionPool deployed) {
        OptionPool implementation = new OptionPool();
        bytes memory initData = abi.encodeCall(OptionPool.initialize, (series_, upgradeAdmin));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        deployed = OptionPool(payable(address(proxy)));
    }

    function _setUpSeriesAndPool() internal {
        oracle = new MockPriceOracle();
        maturity = block.timestamp + 7 days;
        series = _deploySeriesProxy(2000e18, maturity, address(oracle));
        pToken = series.pToken();
        nToken = series.nToken();
        pool = _deployPoolProxy(address(series));
        vm.deal(lp, 100 ether);
        vm.deal(trader, 100 ether);
    }
}

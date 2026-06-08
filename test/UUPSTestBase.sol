// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OptionFactory} from "../src/OptionFactory.sol";
import {OptionSeries} from "../src/OptionSeries.sol";
import {TestBase} from "./TestBase.sol";

contract UUPSTestBase is TestBase {
    bytes32 internal constant ERC1967_IMPLEMENTATION_SLOT =
        bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

    address internal upgradeAdmin = address(0xA11AD);

    function _deploySeriesImplementation() internal returns (OptionSeries implementation) {
        implementation = new OptionSeries();
    }

    function _deploySeriesProxy(uint256 strike, uint256 maturity, address oracle)
        internal
        returns (OptionSeries series)
    {
        OptionSeries implementation = _deploySeriesImplementation();
        series = _deploySeriesProxyWithImplementation(address(implementation), strike, maturity, oracle, upgradeAdmin);
    }

    function _deploySeriesProxyWithImplementation(
        address implementation,
        uint256 strike,
        uint256 maturity,
        address oracle,
        address owner
    ) internal returns (OptionSeries series) {
        bytes memory initData = abi.encodeCall(OptionSeries.initialize, (strike, maturity, oracle, owner));
        ERC1967Proxy proxy = new ERC1967Proxy(implementation, initData);
        series = OptionSeries(address(proxy));
    }

    function _deployFactoryProxy(address seriesImplementation) internal returns (OptionFactory factory) {
        OptionFactory implementation = new OptionFactory();
        bytes memory initData = abi.encodeCall(OptionFactory.initialize, (upgradeAdmin, seriesImplementation));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        factory = OptionFactory(address(proxy));
    }

    function _proxyImplementation(address proxy) internal view returns (address implementation) {
        implementation = address(uint160(uint256(vm.load(proxy, ERC1967_IMPLEMENTATION_SLOT))));
    }
}

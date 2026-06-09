// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PushOracle} from "../src/PushOracle.sol";
import {TestBase} from "./TestBase.sol";

contract PushOracleTest is TestBase {
    PushOracle internal oracle;
    address internal owner = address(0xA11AD);
    address internal keeper = address(0xCAFE);
    bytes32 internal constant FEED = bytes32("ETHUSDC");

    function setUp() public {
        PushOracle impl = new PushOracle();
        bytes memory initData = abi.encodeCall(PushOracle.initialize, (owner, keeper));
        oracle = PushOracle(address(new ERC1967Proxy(address(impl), initData)));
    }

    function testKeeperPushStoresValueAndTime() public {
        vm.warp(1000);
        vm.prank(keeper);
        oracle.pushPrice(FEED, 2500e18);
        (uint256 v, uint256 t) = oracle.getSpotValue(FEED);
        assertEq(v, 2500e18, "value");
        assertEq(t, 1000, "updatedAt");
    }

    function testNonKeeperCannotPush() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(PushOracle.Unauthorized.selector);
        oracle.pushPrice(FEED, 2500e18);
    }

    function testZeroPriceReverts() public {
        vm.prank(keeper);
        vm.expectRevert(PushOracle.ZeroPrice.selector);
        oracle.pushPrice(FEED, 0);
    }

    function testResolveSeriesImplementsIPriceOracle() public {
        address series = address(0x5E21E5);
        vm.prank(keeper);
        oracle.resolveSeries(series, 3000e18);
        (bool resolved, uint256 v) = oracle.getResolvedValue(series);
        assertTrue(resolved, "resolved");
        assertEq(v, 3000e18, "resolved value");
    }
}

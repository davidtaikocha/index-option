// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OptionPool} from "../src/OptionPool.sol";
import {OptionPoolFactory} from "../src/OptionPoolFactory.sol";
import {PoolTestBase} from "./PoolTestBase.sol";

contract OptionPoolUpgradeabilityTest is PoolTestBase {
    function setUp() public {
        _setUpSeriesAndPool();
    }

    function testPoolImplementationRejectsDirectInitialization() public {
        OptionPool impl = new OptionPool();
        vm.expectRevert();
        impl.initialize(address(series), upgradeAdmin);
    }

    function testPoolUpgradeRequiresOwner() public {
        OptionPool newImpl = new OptionPool();
        vm.expectRevert();
        vm.prank(trader);
        pool.upgradeToAndCall(address(newImpl), "");
    }

    function testPoolOwnerCanUpgrade() public {
        OptionPool newImpl = new OptionPool();
        vm.prank(upgradeAdmin);
        pool.upgradeToAndCall(address(newImpl), "");
        assertEq(_proxyImplementation(address(pool)), address(newImpl), "pool upgraded");
    }

    function testFactoryOwnerCanUpgrade() public {
        OptionPool poolImpl = new OptionPool();
        OptionPoolFactory impl = new OptionPoolFactory();
        bytes memory initData = abi.encodeCall(OptionPoolFactory.initialize, (upgradeAdmin, address(poolImpl)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        OptionPoolFactory factory = OptionPoolFactory(address(proxy));

        OptionPoolFactory newImpl = new OptionPoolFactory();
        vm.prank(upgradeAdmin);
        factory.upgradeToAndCall(address(newImpl), "");
        assertEq(_proxyImplementation(address(factory)), address(newImpl), "factory upgraded");
        assertEq(factory.poolImplementation(), address(poolImpl), "impl preserved");
        assertEq(factory.owner(), upgradeAdmin, "owner preserved");
    }

    function testFactoryUpgradeRequiresOwner() public {
        OptionPool poolImpl = new OptionPool();
        OptionPoolFactory impl = new OptionPoolFactory();
        bytes memory initData = abi.encodeCall(OptionPoolFactory.initialize, (upgradeAdmin, address(poolImpl)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        OptionPoolFactory factory = OptionPoolFactory(address(proxy));

        OptionPoolFactory newImpl = new OptionPoolFactory();
        vm.expectRevert();
        vm.prank(trader);
        factory.upgradeToAndCall(address(newImpl), "");
    }
}

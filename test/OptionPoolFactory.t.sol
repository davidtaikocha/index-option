// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OptionPool} from "../src/OptionPool.sol";
import {OptionPoolFactory} from "../src/OptionPoolFactory.sol";
import {OptionSeries} from "../src/OptionSeries.sol";
import {PoolTestBase} from "./PoolTestBase.sol";

contract OptionPoolFactoryTest is PoolTestBase {
    OptionPoolFactory internal factory;

    function setUp() public {
        _setUpSeriesAndPool(); // gives us a series; ignore the standalone pool

        OptionPool poolImpl = new OptionPool();
        OptionPoolFactory impl = new OptionPoolFactory();
        bytes memory initData = abi.encodeCall(OptionPoolFactory.initialize, (upgradeAdmin, address(poolImpl)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        factory = OptionPoolFactory(address(proxy));
    }

    function testCreatePoolDeploysAndRecords() public {
        address poolAddr = factory.createPool(address(series));
        assertEq(factory.poolOf(address(series)), poolAddr, "recorded");

        OptionPool created = OptionPool(payable(poolAddr));
        assertEq(address(created.series()), address(series), "pool series");
        assertEq(address(created.owner()), upgradeAdmin, "pool owner");
    }

    function testCreatePoolRejectsDuplicate() public {
        factory.createPool(address(series));
        vm.expectRevert(OptionPoolFactory.PoolExists.selector);
        factory.createPool(address(series));
    }

    function testSetPoolImplementationOnlyOwner() public {
        OptionPool newImpl = new OptionPool();
        vm.expectRevert();
        vm.prank(trader);
        factory.setPoolImplementation(address(newImpl));

        vm.prank(upgradeAdmin);
        factory.setPoolImplementation(address(newImpl));
        assertEq(factory.poolImplementation(), address(newImpl), "impl updated");
    }

    function testCreatePoolRejectsZeroSeries() public {
        vm.expectRevert(OptionPoolFactory.ZeroSeries.selector);
        factory.createPool(address(0));
    }

    function testInitializeRejectsZeroUpgradeAdmin() public {
        OptionPool poolImpl = new OptionPool();
        OptionPoolFactory impl = new OptionPoolFactory();
        bytes memory initData = abi.encodeCall(OptionPoolFactory.initialize, (address(0), address(poolImpl)));
        vm.expectRevert(OptionPoolFactory.ZeroUpgradeAdmin.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function testInitializeRejectsZeroPoolImplementation() public {
        OptionPoolFactory impl = new OptionPoolFactory();
        bytes memory initData = abi.encodeCall(OptionPoolFactory.initialize, (upgradeAdmin, address(0)));
        vm.expectRevert(OptionPoolFactory.ZeroPoolImplementation.selector);
        new ERC1967Proxy(address(impl), initData);
    }
}

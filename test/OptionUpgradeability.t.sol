// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OptionFactory} from "../src/OptionFactory.sol";
import {OptionSeries} from "../src/OptionSeries.sol";
import {MockPriceOracle} from "./mocks/MockPriceOracle.sol";
import {UUPSTestBase} from "./UUPSTestBase.sol";

contract OptionUpgradeabilityTest is UUPSTestBase {
    MockPriceOracle internal oracle;
    uint256 internal maturity;
    address internal attacker = address(0xBAD);

    function setUp() public {
        oracle = new MockPriceOracle();
        maturity = block.timestamp + 30 days;
    }

    function testSeriesImplementationRejectsDirectInitialization() public {
        OptionSeries implementation = new OptionSeries();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(2000e18, maturity, address(oracle), upgradeAdmin);
    }

    function testFactoryImplementationRejectsDirectInitialization() public {
        OptionSeries seriesImplementation = new OptionSeries();
        OptionFactory factoryImplementation = new OptionFactory();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        factoryImplementation.initialize(upgradeAdmin, address(seriesImplementation));
    }

    function testSeriesUpgradeRequiresOwner() public {
        OptionSeries series = _deploySeriesProxy(2000e18, maturity, address(oracle));
        OptionSeries newImplementation = new OptionSeries();

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, attacker));
        vm.prank(attacker);
        series.upgradeToAndCall(address(newImplementation), "");
    }

    function testSeriesOwnerCanUpgrade() public {
        OptionSeries series = _deploySeriesProxy(2000e18, maturity, address(oracle));
        OptionSeries newImplementation = new OptionSeries();

        vm.prank(upgradeAdmin);
        series.upgradeToAndCall(address(newImplementation), "");

        assertEq(
            _proxyImplementation(address(series)), address(newImplementation), "series implementation after upgrade"
        );
        assertEq(series.owner(), upgradeAdmin, "series owner after upgrade");
        assertEq(series.strike(), 2000e18, "series strike after upgrade");
    }

    function testFactoryUpgradeRequiresOwner() public {
        OptionSeries seriesImplementation = new OptionSeries();
        OptionFactory factory = _deployFactoryProxy(address(seriesImplementation));
        OptionFactory newImplementation = new OptionFactory();

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, attacker));
        vm.prank(attacker);
        factory.upgradeToAndCall(address(newImplementation), "");
    }

    function testFactoryOwnerCanUpgrade() public {
        OptionSeries seriesImplementation = new OptionSeries();
        OptionFactory factory = _deployFactoryProxy(address(seriesImplementation));
        OptionFactory newImplementation = new OptionFactory();

        vm.prank(upgradeAdmin);
        factory.upgradeToAndCall(address(newImplementation), "");

        assertEq(
            _proxyImplementation(address(factory)), address(newImplementation), "factory implementation after upgrade"
        );
        assertEq(factory.owner(), upgradeAdmin, "factory owner after upgrade");
        assertEq(factory.seriesImplementation(), address(seriesImplementation), "implementation after upgrade");
    }

    function testSetSeriesImplementationRequiresOwner() public {
        OptionSeries oldImplementation = new OptionSeries();
        OptionSeries newImplementation = new OptionSeries();
        OptionFactory factory = _deployFactoryProxy(address(oldImplementation));

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, attacker));
        vm.prank(attacker);
        factory.setSeriesImplementation(address(newImplementation));
    }

    function testOwnerCanSetSeriesImplementationForFutureSeries() public {
        OptionSeries oldImplementation = new OptionSeries();
        OptionSeries newImplementation = new OptionSeries();
        OptionFactory factory = _deployFactoryProxy(address(oldImplementation));

        vm.prank(upgradeAdmin);
        factory.setSeriesImplementation(address(newImplementation));

        assertEq(factory.seriesImplementation(), address(newImplementation), "new series implementation");

        address seriesAddress = factory.createSeries(2500e18, maturity, address(oracle));
        OptionSeries series = OptionSeries(seriesAddress);

        assertEq(_proxyImplementation(seriesAddress), address(newImplementation), "future series implementation");
        assertEq(series.strike(), 2500e18, "future series strike");
        assertEq(series.maturity(), maturity, "future series maturity");
        assertEq(address(series.oracle()), address(oracle), "future series oracle");
        assertEq(series.owner(), upgradeAdmin, "future series owner");
    }

    function testFactoryInitializeRejectsZeroUpgradeAdmin() public {
        OptionSeries seriesImplementation = new OptionSeries();
        OptionFactory factoryImplementation = new OptionFactory();
        bytes memory initData = abi.encodeCall(OptionFactory.initialize, (address(0), address(seriesImplementation)));

        vm.expectRevert(OptionFactory.ZeroUpgradeAdmin.selector);
        new ERC1967Proxy(address(factoryImplementation), initData);
    }

    function testFactoryInitializeRejectsZeroSeriesImplementation() public {
        OptionFactory factoryImplementation = new OptionFactory();
        bytes memory initData = abi.encodeCall(OptionFactory.initialize, (upgradeAdmin, address(0)));

        vm.expectRevert(OptionFactory.ZeroSeriesImplementation.selector);
        new ERC1967Proxy(address(factoryImplementation), initData);
    }

    function testSeriesInitializeRejectsZeroUpgradeAdmin() public {
        OptionSeries implementation = new OptionSeries();
        bytes memory initData =
            abi.encodeCall(OptionSeries.initialize, (2000e18, maturity, address(oracle), address(0)));

        vm.expectRevert(OptionSeries.ZeroUpgradeAdmin.selector);
        new ERC1967Proxy(address(implementation), initData);
    }
}

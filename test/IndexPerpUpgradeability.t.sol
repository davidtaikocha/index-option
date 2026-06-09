// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IndexPerp} from "../src/IndexPerp.sol";
import {PerpVault} from "../src/PerpVault.sol";
import {PushOracle} from "../src/PushOracle.sol";
import {IndexBasket} from "../src/IndexBasket.sol";
import {InsuranceFund} from "../src/InsuranceFund.sol";
import {IndexPerpTestBase} from "./IndexPerpTestBase.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract IndexPerpUpgradeabilityTest is IndexPerpTestBase {
    bytes32 internal constant IMPL_SLOT = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

    function setUp() public {
        _setUpPerp(100 ether, 10 ether, 4000e18);
    }

    function _impl(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, IMPL_SLOT))));
    }

    function testOwnerCanUpgradePerp() public {
        address newImpl = address(new IndexPerp());
        vm.prank(owner);
        UUPSUpgradeable(address(perp)).upgradeToAndCall(newImpl, "");
        assertEq(_impl(address(perp)), newImpl, "impl swapped");
    }

    function testNonOwnerCannotUpgradePerp() public {
        address newImpl = address(new IndexPerp());
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        UUPSUpgradeable(address(perp)).upgradeToAndCall(newImpl, "");
    }

    function testNonOwnerCannotUpgradeVault() public {
        address newImpl = address(new PerpVault());
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        UUPSUpgradeable(address(vault)).upgradeToAndCall(newImpl, "");
    }

    function testOwnerCanUpgradeVault() public {
        address newImpl = address(new PerpVault());
        vm.prank(owner);
        UUPSUpgradeable(address(vault)).upgradeToAndCall(newImpl, "");
        assertEq(_impl(address(vault)), newImpl, "vault impl swapped");
    }

    function testOwnerCanUpgradeOracleAndNonOwnerCannot() public {
        address newImpl = address(new PushOracle());
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        UUPSUpgradeable(address(oracle)).upgradeToAndCall(newImpl, "");
        vm.prank(owner);
        UUPSUpgradeable(address(oracle)).upgradeToAndCall(newImpl, "");
        assertEq(_impl(address(oracle)), newImpl, "oracle impl swapped");
    }

    function testOwnerCanUpgradeBasketAndNonOwnerCannot() public {
        address newImpl = address(new IndexBasket());
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        UUPSUpgradeable(address(basket)).upgradeToAndCall(newImpl, "");
        vm.prank(owner);
        UUPSUpgradeable(address(basket)).upgradeToAndCall(newImpl, "");
        assertEq(_impl(address(basket)), newImpl, "basket impl swapped");
    }

    function testOwnerCanUpgradeInsuranceAndNonOwnerCannot() public {
        address newImpl = address(new InsuranceFund());
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        UUPSUpgradeable(address(insurance)).upgradeToAndCall(newImpl, "");
        vm.prank(owner);
        UUPSUpgradeable(address(insurance)).upgradeToAndCall(newImpl, "");
        assertEq(_impl(address(insurance)), newImpl, "insurance impl swapped");
    }
}

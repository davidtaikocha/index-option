// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PerpVault} from "../src/PerpVault.sol";
import {TestBase} from "./TestBase.sol";

contract PerpVaultTest is TestBase {
    PerpVault internal vault;
    address internal owner = address(0xA11AD);
    address internal perp = address(0x9E97);
    address internal lp = address(0x11D);

    function setUp() public {
        PerpVault impl = new PerpVault();
        vault = PerpVault(payable(address(new ERC1967Proxy(address(impl), abi.encodeCall(PerpVault.initialize, (owner, 8000))))));
        vm.prank(owner);
        vault.setPerp(perp);
        vm.deal(lp, 100 ether);
        vm.deal(perp, 100 ether);
    }

    function testFirstDepositMintsSharesOneToOne() public {
        vm.prank(lp);
        uint256 shares = vault.deposit{value: 10 ether}();
        assertEq(shares, 10 ether, "1:1 first deposit");
        assertEq(vault.totalAssets(), 10 ether, "assets");
    }

    function testReserveRespectsUtilizationCap() public {
        vm.prank(lp);
        vault.deposit{value: 10 ether}();
        // cap = 80% of 10 = 8 ether
        vm.prank(perp);
        vm.expectRevert(PerpVault.UtilizationExceeded.selector);
        vault.reserve(9 ether);
        vm.prank(perp);
        vault.reserve(8 ether); // ok
        assertEq(vault.reserved(), 8 ether, "reserved");
    }

    function testWithdrawCannotTakeReserved() public {
        vm.prank(lp);
        uint256 shares = vault.deposit{value: 10 ether}();
        vm.prank(perp);
        vault.reserve(8 ether);
        vm.prank(lp);
        vm.expectRevert(PerpVault.InsufficientFreeAssets.selector);
        vault.withdraw(shares); // wants 10 but only 2 free
    }

    function testTakeLossRaisesSharePrice() public {
        vm.prank(lp);
        uint256 shares = vault.deposit{value: 10 ether}();
        vm.prank(perp);
        vault.takeLoss{value: 2 ether}();
        // now 12 ether backs `shares`; withdraw returns 12
        vm.prank(lp);
        uint256 out = vault.withdraw(shares);
        assertEq(out, 12 ether, "share price rose");
    }

    function testOnlyPerpGuards() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(PerpVault.OnlyPerp.selector);
        vault.reserve(1 ether);
    }

    function testDepositAfterFullDrainResetsOneToOne() public {
        vm.prank(lp);
        vault.deposit{value: 10 ether}();
        // perp pays out the entire balance: balance 0, totalShares > 0
        vm.prank(perp);
        vault.payProfit(address(0xD5A1), 10 ether);
        assertEq(vault.totalAssets(), 0, "vault drained");
        // a new deposit must not panic; prices 1:1 on the recapitalized amount
        address lp2 = address(0x11D2);
        vm.deal(lp2, 5 ether);
        vm.prank(lp2);
        uint256 shares = vault.deposit{value: 5 ether}();
        assertEq(shares, 5 ether, "1:1 reset on drained vault");
    }
}

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
        // now ~12 ether backs `shares`; withdraw returns ~12 (virtual offset costs <1e9 wei dust)
        vm.prank(lp);
        uint256 out = vault.withdraw(shares);
        assertLe(out, 12 ether, "never over 12");
        assertLe(12 ether - out, 1e9, "share price rose to ~12");
    }

    function testOnlyPerpGuards() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(PerpVault.OnlyPerp.selector);
        vault.reserve(1 ether);
    }

    function testDepositAfterFullDrainRecapitalizes() public {
        vm.prank(lp);
        vault.deposit{value: 10 ether}();
        // perp pays out the entire balance: balance 0, old shares now worthless
        vm.prank(perp);
        vault.payProfit(address(0xD5A1), 10 ether);
        assertEq(vault.totalAssets(), 0, "vault drained");
        // a new deposit must not panic; the recapitalizing LP can recover ~their deposit
        address lp2 = address(0x11D2);
        vm.deal(lp2, 5 ether);
        vm.prank(lp2);
        uint256 shares = vault.deposit{value: 5 ether}();
        assertTrue(shares > 0, "deposit succeeds after drain");
        vm.prank(lp2);
        uint256 out = vault.withdraw(shares);
        assertLe(out, 5 ether, "never over deposit");
        assertLe(5 ether - out, 1e9, "recovers ~full deposit; old shares worthless");
    }

    // First-depositor share-inflation attack must be unprofitable even when the vault
    // balance is inflated without minting shares.
    function testInflationAttackUnprofitable() public {
        address attacker = address(0xA77AC);
        address victim = address(0x71C7);
        vm.deal(attacker, 1 ether);
        vm.deal(victim, 11 ether);

        // attacker is the first depositor with a dust amount
        vm.prank(attacker);
        uint256 aShares = vault.deposit{value: 1}();

        // balance inflated by 10 ETH without new shares (simulates a forced donation)
        vm.prank(perp);
        vault.takeLoss{value: 10 ether}();

        // victim deposits and must still receive a meaningful, non-zero share amount
        vm.prank(victim);
        uint256 vShares = vault.deposit{value: 11 ether}();
        assertTrue(vShares > 0, "victim not griefed to zero shares");

        // attacker withdraws their dust share: cannot extract the victim's deposit
        vm.prank(attacker);
        uint256 aOut = vault.withdraw(aShares);
        assertLe(aOut, 1 ether, "attacker cannot profit by stealing victim funds");
    }
}

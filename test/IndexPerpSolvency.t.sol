// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IndexPerpTestBase} from "./IndexPerpTestBase.sol";

contract IndexPerpSolvencyTest is IndexPerpTestBase {
    function setUp() public {
        _setUpPerp(1_000 ether, 100 ether, 4000e18);
        vm.prank(owner);
        perp.setParams(20e18, 10, 10, 1e8, 1e8, 500, 500);
    }

    /// After any sequence of opens at varied prices, vault balance never drops below
    /// its reserved amount (LP reserved capital is never spent on open).
    function testFuzzVaultBalanceCoversReserved(uint96 a, uint96 b, uint96 c) public {
        uint256[3] memory margins = [(uint256(a) % 3 ether) + 0.1 ether, (uint256(b) % 3 ether) + 0.1 ether, (uint256(c) % 3 ether) + 0.1 ether];
        for (uint256 i; i < 3; ++i) {
            bool isLong = i % 2 == 0;
            // limitLevel must match direction or short opens always revert on slippage.
            vm.prank(trader);
            try perp.open{value: margins[i]}(isLong, 5e18, isLong ? type(uint256).max : 0) {} catch {}
        }
        assertTrue(vault.totalAssets() >= vault.reserved(), "vault covers reserved");
    }
}

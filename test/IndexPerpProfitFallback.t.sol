// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IndexPerpTestBase} from "./IndexPerpTestBase.sol";

// When a winning trader is owed more than the vault holds, the profit branch pays
// what the vault has and draws the remainder from the insurance fund — the close
// must never revert and strand the trader.
contract IndexPerpProfitFallbackTest is IndexPerpTestBase {
    function setUp() public {
        // small vault (10 ETH), well-funded insurance (200 ETH), open near the band floor
        // so a move to the top of the band produces profit far exceeding the vault.
        _setUpPerp(10 ether, 200 ether, 2100e18);
        vm.prank(owner);
        perp.setParams(20e18, 0, 0, 0, 0, 500, 500); // no fees for clean accounting
    }

    function testProfitBeyondVaultIsCoveredByInsurance() public {
        // entry level ~0.0476 at price 2100; notional 5 ETH (reservable against 10 ETH vault)
        vm.prank(trader);
        uint256 id = perp.open{value: 1 ether}(true, 5e18, type(uint256).max);

        uint256 vaultBefore = vault.totalAssets();
        uint256 insBefore = address(insurance).balance;
        uint256 traderBefore = trader.balance;

        // jump to the top of the band: level 0.8, profit (~79 ETH) >> vault balance
        _push(10000e18);
        vm.prank(trader);
        int256 pnl = perp.close(id, 0);

        assertTrue(pnl > int256(vaultBefore), "profit exceeds vault balance");
        // trader received margin + full profit despite the under-funded vault (no revert/strand)
        assertTrue(trader.balance - traderBefore > vaultBefore, "trader paid beyond vault");
        // vault contributed its balance; insurance covered the remainder
        assertTrue(address(insurance).balance < insBefore, "insurance covered the shortfall");
        (address o,,,,,,,) = perp.positions(id);
        assertEq(o, address(0), "position closed");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IndexPerpTestBase} from "./IndexPerpTestBase.sol";

contract IndexPerpFuzzTest is IndexPerpTestBase {
    function setUp() public {
        _setUpPerp(1_000 ether, 100 ether, 4000e18);
        vm.prank(owner);
        perp.setParams(20e18, 10, 10, 1e8, 1e8, 500, 500);
    }

    /// Total ETH across perp + vault + insurance + trader is conserved across an
    /// open→(price move)→close round-trip (no ETH created or destroyed).
    function testFuzzOpenCloseConservesEth(uint96 marginRaw, uint16 levRaw, uint96 priceRaw, bool isLong) public {
        uint256 margin = (uint256(marginRaw) % 5 ether) + 0.01 ether;
        uint256 leverage = ((uint256(levRaw) % 19) + 1) * 1e18; // 1x..20x
        uint256 price = (uint256(priceRaw) % 7000e18) + 2200e18; // 2200..9200, all > strike+band

        uint256 totalBefore = address(perp).balance + vault.totalAssets() + address(insurance).balance + trader.balance;

        vm.prank(trader);
        try perp.open{value: margin}(isLong, leverage, isLong ? type(uint256).max : 0) returns (uint256 id) {
            vm.warp(block.timestamp + (uint256(priceRaw) % 5000));
            _push(price);
            vm.prank(trader);
            try perp.close(id, isLong ? 0 : type(uint256).max) {} catch {}
        } catch {}

        uint256 totalAfter = address(perp).balance + vault.totalAssets() + address(insurance).balance + trader.balance;
        // allow only integer-division dust (~tens of wei per round-trip); tight enough
        // to catch any systematic leak.
        if (totalAfter > totalBefore) {
            assertLe(totalAfter - totalBefore, 1e4, "no ETH created");
        } else {
            assertLe(totalBefore - totalAfter, 1e4, "no ETH destroyed");
        }
    }
}

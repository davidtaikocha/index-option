// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PushOracle} from "../src/PushOracle.sol";
import {IndexBasket} from "../src/IndexBasket.sol";
import {TestBase} from "./TestBase.sol";

contract IndexBasketTest is TestBase {
    PushOracle internal oracle;
    IndexBasket internal basket;
    address internal owner = address(0xA11AD);
    address internal keeper = address(0xCAFE);
    bytes32 internal constant FEED = bytes32("ETHUSDC");

    function _deployOracle() internal {
        PushOracle impl = new PushOracle();
        oracle = PushOracle(address(new ERC1967Proxy(address(impl), abi.encodeCall(PushOracle.initialize, (owner, keeper)))));
    }

    // single CALL leg @ K=2000, weight 1e18 -> level = max(0, 1 - 2000/x)
    function _deployBasket() internal {
        IndexBasket.IndexLeg[] memory legs = new IndexBasket.IndexLeg[](1);
        legs[0] = IndexBasket.IndexLeg({kind: IndexBasket.LegKind.CALL, strike: 2000e18, weight: 1e18});
        IndexBasket impl = new IndexBasket();
        bytes memory initData = abi.encodeCall(
            IndexBasket.initialize, (owner, address(oracle), FEED, 1 hours, 2100e18, 10000e18, legs)
        );
        basket = IndexBasket(address(new ERC1967Proxy(address(impl), initData)));
    }

    function setUp() public {
        _deployOracle();
        _deployBasket();
    }

    function testLevelMatchesCallFormula() public {
        // x=4000 -> 1 - 2000/4000 = 0.5e18
        assertEq(basket.levelEth(4000e18), 0.5e18, "call level at 4000");
        // x=2500 -> 1 - 2000/2500 = 0.2e18
        assertEq(basket.levelEth(2500e18), 0.2e18, "call level at 2500");
    }

    function testCallBelowStrikeIsZeroLevelReverts() public {
        // x=2000 -> payoff 0 -> level 0 -> NonPositiveLevel
        vm.expectRevert(IndexBasket.NonPositiveLevel.selector);
        basket.levelEth(2000e18);
    }

    function testCurrentLevelReadsFreshSpot() public {
        vm.warp(1000);
        vm.prank(keeper);
        oracle.pushPrice(FEED, 4000e18);
        assertEq(basket.currentLevel(), 0.5e18, "current level");
    }

    function testCurrentLevelRevertsWhenStale() public {
        vm.warp(1000);
        vm.prank(keeper);
        oracle.pushPrice(FEED, 4000e18);
        vm.warp(1000 + 1 hours + 1);
        vm.expectRevert(IndexBasket.StalePrice.selector);
        basket.currentLevel();
    }

    function testEmptyBasketReverts() public {
        IndexBasket.IndexLeg[] memory legs = new IndexBasket.IndexLeg[](0);
        IndexBasket impl = new IndexBasket();
        vm.expectRevert(IndexBasket.EmptyBasket.selector);
        new ERC1967Proxy(address(impl), abi.encodeCall(
            IndexBasket.initialize, (owner, address(oracle), FEED, 1 hours, 2100e18, 10000e18, legs)
        ));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ClaimToken} from "../src/ClaimToken.sol";
import {TestBase} from "./TestBase.sol";

contract ClaimTokenTest is TestBase {
    ClaimToken internal token;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCA20);

    function setUp() public {
        token = new ClaimToken("P USD/ETH", "pUSD");
    }

    function testSeriesCanMintAndBurn() public {
        token.mint(alice, 5 ether);

        assertEq(token.totalSupply(), 5 ether, "total supply after mint");
        assertEq(token.balanceOf(alice), 5 ether, "alice balance after mint");

        token.burn(alice, 2 ether);

        assertEq(token.totalSupply(), 3 ether, "total supply after burn");
        assertEq(token.balanceOf(alice), 3 ether, "alice balance after burn");
    }

    function testNonSeriesCannotMint() public {
        vm.expectRevert(ClaimToken.Unauthorized.selector);
        vm.prank(alice);
        token.mint(alice, 1 ether);
    }

    function testTransferAndTransferFrom() public {
        token.mint(alice, 10 ether);

        vm.prank(alice);
        token.transfer(bob, 3 ether);

        assertEq(token.balanceOf(alice), 7 ether, "alice balance after transfer");
        assertEq(token.balanceOf(bob), 3 ether, "bob balance after transfer");

        vm.prank(bob);
        token.approve(carol, 1 ether);

        vm.prank(carol);
        token.transferFrom(bob, alice, 1 ether);

        assertEq(token.balanceOf(alice), 8 ether, "alice balance after transferFrom");
        assertEq(token.balanceOf(bob), 2 ether, "bob balance after transferFrom");
        assertEq(token.allowance(bob, carol), 0, "allowance after transferFrom");
    }
}

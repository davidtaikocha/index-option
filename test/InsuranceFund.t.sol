// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {InsuranceFund} from "../src/InsuranceFund.sol";
import {TestBase, Vm} from "./TestBase.sol";

contract InsuranceFundTest is TestBase {
    InsuranceFund internal fund;
    address internal owner = address(0xA11AD);
    address internal perp = address(0x9E97);
    address internal sink = address(0x5114);

    function setUp() public {
        InsuranceFund impl = new InsuranceFund();
        fund = InsuranceFund(payable(address(new ERC1967Proxy(address(impl), abi.encodeCall(InsuranceFund.initialize, (owner))))));
        vm.prank(owner);
        fund.setPerp(perp);
        vm.deal(address(this), 100 ether);
        fund.deposit{value: 10 ether}();
    }

    function testCoverShortfallPaysRequestedWhenSolvent() public {
        vm.prank(perp);
        uint256 paid = fund.coverShortfall(sink, 4 ether);
        assertEq(paid, 4 ether, "paid full");
        assertEq(sink.balance, 4 ether, "sink received");
    }

    function testCoverShortfallCapsAtBalanceAndEmitsBadDebt() public {
        vm.recordLogs();
        vm.prank(perp);
        uint256 paid = fund.coverShortfall(sink, 25 ether);
        assertEq(paid, 10 ether, "capped at balance");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool sawBadDebt;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == keccak256("BadDebt(uint256)")) sawBadDebt = true;
        }
        assertTrue(sawBadDebt, "BadDebt emitted");
    }

    function testOnlyPerpCanCover() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(InsuranceFund.OnlyPerp.selector);
        fund.coverShortfall(sink, 1 ether);
    }

    function testOwnerWithdrawsSurplus() public {
        vm.prank(owner);
        fund.withdraw(3 ether, sink);
        assertEq(sink.balance, 3 ether, "surplus withdrawn");
    }
}

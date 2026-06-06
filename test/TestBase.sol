// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface Vm {
    function warp(uint256 newTimestamp) external;
    function deal(address account, uint256 newBalance) external;
    function prank(address account) external;
    function expectRevert(bytes4 selector) external;
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData) external;
}

contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    receive() external payable {}

    function assertTrue(bool value, string memory message) internal pure {
        if (!value) revert(message);
    }

    function assertFalse(bool value, string memory message) internal pure {
        if (value) revert(message);
    }

    function assertEq(uint256 actual, uint256 expected, string memory message) internal pure {
        if (actual != expected) revert(message);
    }

    function assertEq(address actual, address expected, string memory message) internal pure {
        if (actual != expected) revert(message);
    }

    function assertLe(uint256 actual, uint256 expected, string memory message) internal pure {
        if (actual > expected) revert(message);
    }

    function assertStrEq(string memory actual, string memory expected, string memory message) internal pure {
        if (keccak256(bytes(actual)) != keccak256(bytes(expected))) revert(message);
    }
}

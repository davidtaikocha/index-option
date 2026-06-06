// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ClaimToken } from "./ClaimToken.sol";
import { IPriceOracle } from "./interfaces/IPriceOracle.sol";

contract OptionSeries {
    uint256 public constant ONE = 1e18;

    string public ticker;
    uint256 public immutable strike;
    uint256 public immutable maturity;
    IPriceOracle public immutable oracle;
    ClaimToken public immutable pToken;
    ClaimToken public immutable nToken;

    error ZeroStrike();
    error ZeroMaturity();
    error ZeroOracle();
    error ZeroAmount();
    error SplitAfterMaturity();
    error InvalidRecipient();
    error EthTransferFailed();

    event Split(address indexed user, address indexed receiver, uint256 amount);
    event Combined(address indexed user, address indexed receiver, uint256 amount);

    constructor(
        string memory ticker_,
        uint256 strike_,
        uint256 maturity_,
        address oracle_,
        string memory pName_,
        string memory pSymbol_,
        string memory nName_,
        string memory nSymbol_
    ) {
        if (strike_ == 0) revert ZeroStrike();
        if (maturity_ == 0) revert ZeroMaturity();
        if (oracle_ == address(0)) revert ZeroOracle();

        ticker = ticker_;
        strike = strike_;
        maturity = maturity_;
        oracle = IPriceOracle(oracle_);
        pToken = new ClaimToken(pName_, pSymbol_);
        nToken = new ClaimToken(nName_, nSymbol_);
    }

    function split(address receiver) external payable returns (uint256 amount) {
        if (msg.value == 0) revert ZeroAmount();
        if (block.timestamp >= maturity) revert SplitAfterMaturity();

        amount = msg.value;
        pToken.mint(receiver, amount);
        nToken.mint(receiver, amount);

        emit Split(msg.sender, receiver, amount);
    }

    function combine(uint256 amount, address receiver) external {
        if (amount == 0) revert ZeroAmount();
        if (receiver == address(0)) revert InvalidRecipient();

        pToken.burn(msg.sender, amount);
        nToken.burn(msg.sender, amount);
        _sendETH(receiver, amount);

        emit Combined(msg.sender, receiver, amount);
    }

    function _sendETH(address receiver, uint256 amount) internal {
        if (amount == 0) return;
        if (receiver == address(0)) revert InvalidRecipient();

        (bool ok, ) = receiver.call{ value: amount }("");
        if (!ok) revert EthTransferFailed();
    }
}

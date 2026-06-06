// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ClaimToken } from "./ClaimToken.sol";
import { IPriceOracle } from "./interfaces/IPriceOracle.sol";

contract OptionSeries {
    uint256 public constant ONE = 1e18;
    uint256 public constant MAX_AMOUNT = type(uint256).max / ONE - 1;

    string public ticker;
    uint256 public immutable strike;
    uint256 public immutable maturity;
    IPriceOracle public immutable oracle;
    ClaimToken public immutable pToken;
    ClaimToken public immutable nToken;
    bool public settled;
    uint256 public resolvedValue;
    uint256 public payoutP;
    uint256 public payoutN;
    uint256 public pRemainder;
    uint256 public nRemainder;

    error ZeroStrike();
    error StrikeTooLarge();
    error ZeroMaturity();
    error ZeroOracle();
    error ZeroAmount();
    error AmountTooLarge();
    error SplitAfterMaturity();
    error CombineAfterSettlement();
    error SettleBeforeMaturity();
    error OracleUnresolved();
    error InvalidOracleValue();
    error AlreadySettled();
    error RedeemBeforeSettlement();
    error InvalidRecipient();
    error EthTransferFailed();

    event Split(address indexed user, address indexed receiver, uint256 amount);
    event Combined(address indexed user, address indexed receiver, uint256 amount);
    event Settled(uint256 resolvedValue, uint256 payoutP, uint256 payoutN);
    event Redeemed(
        address indexed user,
        address indexed receiver,
        address indexed token,
        uint256 amount,
        uint256 ethPaid
    );

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
        if (strike_ > type(uint256).max / ONE) revert StrikeTooLarge();
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
        if (msg.value > MAX_AMOUNT) revert AmountTooLarge();
        if (block.timestamp >= maturity) revert SplitAfterMaturity();

        amount = msg.value;
        pToken.mint(receiver, amount);
        nToken.mint(receiver, amount);

        emit Split(msg.sender, receiver, amount);
    }

    function combine(uint256 amount, address receiver) external {
        if (settled) revert CombineAfterSettlement();
        if (amount == 0) revert ZeroAmount();
        if (receiver == address(0)) revert InvalidRecipient();

        pToken.burn(msg.sender, amount);
        nToken.burn(msg.sender, amount);
        _sendETH(receiver, amount);

        emit Combined(msg.sender, receiver, amount);
    }

    function settle() external {
        if (settled) revert AlreadySettled();
        if (block.timestamp < maturity) revert SettleBeforeMaturity();

        (bool isResolved, uint256 value) = oracle.getResolvedValue(address(this));
        if (!isResolved) revert OracleUnresolved();
        if (value == 0) revert InvalidOracleValue();

        uint256 pPayout = strike >= value ? ONE : (strike * ONE) / value;
        uint256 nPayout = ONE - pPayout;

        resolvedValue = value;
        payoutP = pPayout;
        payoutN = nPayout;
        settled = true;

        emit Settled(value, pPayout, nPayout);
    }

    function redeemP(uint256 amount, address receiver) external returns (uint256 ethPaid) {
        ethPaid = _redeem(pToken, payoutP, amount, receiver, true);
    }

    function redeemN(uint256 amount, address receiver) external returns (uint256 ethPaid) {
        ethPaid = _redeem(nToken, payoutN, amount, receiver, false);
    }

    function _redeem(
        ClaimToken token,
        uint256 payout,
        uint256 amount,
        address receiver,
        bool isPToken
    )
        internal
        returns (uint256 ethPaid)
    {
        if (!settled) revert RedeemBeforeSettlement();
        if (amount == 0) revert ZeroAmount();
        if (amount > MAX_AMOUNT) revert AmountTooLarge();
        if (receiver == address(0)) revert InvalidRecipient();

        uint256 numerator = amount * payout + (isPToken ? pRemainder : nRemainder);
        uint256 newRemainder = numerator % ONE;
        ethPaid = numerator / ONE;

        token.burn(msg.sender, amount);
        if (isPToken) {
            pRemainder = newRemainder;
        } else {
            nRemainder = newRemainder;
        }
        _sendETH(receiver, ethPaid);

        emit Redeemed(msg.sender, receiver, address(token), amount, ethPaid);
    }

    function _sendETH(address receiver, uint256 amount) internal {
        if (receiver == address(0)) revert InvalidRecipient();
        if (amount == 0) return;

        (bool ok, ) = receiver.call{ value: amount }("");
        if (!ok) revert EthTransferFailed();
    }
}

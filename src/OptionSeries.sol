// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ClaimToken} from "./ClaimToken.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";

/// @title OptionSeries
/// @notice ETH-collateralized ETH/USDC P/N option series for one strike and maturity.
/// @dev Users split ETH into equal P and N claims. Before settlement, matching
///      P/N claims can always be recombined into ETH. After maturity, a slow
///      oracle resolves the ETH/USDC price and P/N claims redeem against fixed
///      complementary payout ratios whose sum is exactly 1e18.
contract OptionSeries {
    /// @notice Fixed-point scale used for strikes, resolved values, and payouts.
    uint256 public constant ONE = 1e18;
    /// @notice Upper bound that keeps `amount * payout + remainder` overflow-safe.
    uint256 public constant MAX_AMOUNT = type(uint256).max / ONE - 1;

    /// @notice 1e18 fixed-point ETH/USDC strike price.
    uint256 public immutable strike;
    /// @notice Timestamp after which settlement can be performed.
    uint256 public immutable maturity;
    /// @notice Oracle queried once at settlement for the ETH/USDC price.
    IPriceOracle public immutable oracle;
    /// @notice P-side claim token.
    ClaimToken public immutable pToken;
    /// @notice N-side claim token.
    ClaimToken public immutable nToken;
    /// @notice Whether the series has been settled.
    bool public settled;
    /// @notice ETH/USDC oracle price used at settlement.
    uint256 public resolvedValue;
    /// @notice ETH payout per P claim token, scaled by 1e18.
    uint256 public payoutP;
    /// @notice ETH payout per N claim token, scaled by 1e18.
    uint256 public payoutN;
    /// @notice Fractional P-side payout remainder carried across redemptions.
    uint256 public pRemainder;
    /// @notice Fractional N-side payout remainder carried across redemptions.
    uint256 public nRemainder;

    /// @notice Strike cannot be zero.
    error ZeroStrike();
    /// @notice Strike is too large for safe fixed-point settlement math.
    error StrikeTooLarge();
    /// @notice Maturity timestamp cannot be zero.
    error ZeroMaturity();
    /// @notice Oracle address cannot be zero.
    error ZeroOracle();
    /// @notice Amount cannot be zero.
    error ZeroAmount();
    /// @notice Amount is too large for safe fixed-point redemption math.
    error AmountTooLarge();
    /// @notice Splits are only allowed before maturity.
    error SplitAfterMaturity();
    /// @notice Combining P/N claims is disabled after settlement.
    error CombineAfterSettlement();
    /// @notice Settlement can only happen at or after maturity.
    error SettleBeforeMaturity();
    /// @notice Oracle has not resolved this series yet.
    error OracleUnresolved();
    /// @notice Oracle resolved an invalid zero value.
    error InvalidOracleValue();
    /// @notice Settlement has already been finalized.
    error AlreadySettled();
    /// @notice P/N redemptions require settlement first.
    error RedeemBeforeSettlement();
    /// @notice Receiver cannot be the zero address.
    error InvalidRecipient();
    /// @notice Native ETH transfer failed.
    error EthTransferFailed();

    /// @notice Emitted when ETH is split into equal P and N claims.
    /// @param user Caller that supplied ETH.
    /// @param receiver Account receiving minted P and N claims.
    /// @param amount ETH amount split and claim amount minted per side.
    event Split(address indexed user, address indexed receiver, uint256 amount);
    /// @notice Emitted when equal P and N claims are recombined into ETH.
    /// @param user Caller whose P and N claims were burned.
    /// @param receiver Account receiving returned ETH.
    /// @param amount Claim amount burned per side and ETH amount returned.
    event Combined(address indexed user, address indexed receiver, uint256 amount);
    /// @notice Emitted once the oracle value is bound and payouts are fixed.
    /// @param resolvedValue Oracle value used for settlement.
    /// @param payoutP ETH payout per P claim token, scaled by 1e18.
    /// @param payoutN ETH payout per N claim token, scaled by 1e18.
    event Settled(uint256 resolvedValue, uint256 payoutP, uint256 payoutN);
    /// @notice Emitted when a P or N holder redeems settled claims for ETH.
    /// @param user Caller whose claim tokens were burned.
    /// @param receiver Account receiving ETH payout.
    /// @param token Claim token redeemed, either `pToken` or `nToken`.
    /// @param amount Claim amount burned.
    /// @param ethPaid ETH amount sent to `receiver`.
    event Redeemed(
        address indexed user, address indexed receiver, address indexed token, uint256 amount, uint256 ethPaid
    );

    /// @param strike_ 1e18 fixed-point ETH/USDC strike price.
    /// @param maturity_ Timestamp after which settlement is allowed.
    /// @param oracle_ Oracle contract implementing `IPriceOracle`.
    constructor(uint256 strike_, uint256 maturity_, address oracle_) {
        if (strike_ == 0) revert ZeroStrike();
        if (strike_ > type(uint256).max / ONE) revert StrikeTooLarge();
        if (maturity_ == 0) revert ZeroMaturity();
        if (oracle_ == address(0)) revert ZeroOracle();

        strike = strike_;
        maturity = maturity_;
        oracle = IPriceOracle(oracle_);
        pToken = new ClaimToken("Protected ETH/USDC", "pETHUSDC");
        nToken = new ClaimToken("Complement ETH/USDC", "nETHUSDC");
    }

    /// @notice Splits ETH into equal P and N claim tokens before maturity.
    /// @dev Each wei deposited mints one P token unit and one N token unit.
    /// @param receiver Account receiving both minted claim tokens.
    /// @return amount ETH amount deposited and claim amount minted per side.
    function split(address receiver) external payable returns (uint256 amount) {
        if (msg.value == 0) revert ZeroAmount();
        if (msg.value > MAX_AMOUNT) revert AmountTooLarge();
        if (block.timestamp >= maturity) revert SplitAfterMaturity();

        amount = msg.value;
        pToken.mint(receiver, amount);
        nToken.mint(receiver, amount);

        emit Split(msg.sender, receiver, amount);
    }

    /// @notice Burns equal P and N claim amounts and returns ETH before settlement.
    /// @dev Combining remains available after maturity until the oracle value is
    ///      bound, because P plus N still represents exactly one unit of ETH.
    /// @param amount Claim amount to burn from each side.
    /// @param receiver Account receiving returned ETH.
    function combine(uint256 amount, address receiver) external {
        if (settled) revert CombineAfterSettlement();
        if (amount == 0) revert ZeroAmount();
        if (receiver == address(0)) revert InvalidRecipient();

        pToken.burn(msg.sender, amount);
        nToken.burn(msg.sender, amount);
        _sendETH(receiver, amount);

        emit Combined(msg.sender, receiver, amount);
    }

    /// @notice Finalizes settlement payouts from the oracle after maturity.
    /// @dev With resolved ETH/USDC price `x`, P receives `min(1, strike / x)` ETH
    ///      per claim and N receives the complementary payout. Payouts are scaled
    ///      by 1e18 and sum to exactly `ONE`.
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

    /// @notice Redeems settled P claims for ETH.
    /// @param amount P claim amount to burn.
    /// @param receiver Account receiving the ETH payout.
    /// @return ethPaid ETH amount sent to `receiver`.
    function redeemP(uint256 amount, address receiver) external returns (uint256 ethPaid) {
        ethPaid = _redeem(pToken, payoutP, amount, receiver, true);
    }

    /// @notice Redeems settled N claims for ETH.
    /// @param amount N claim amount to burn.
    /// @param receiver Account receiving the ETH payout.
    /// @return ethPaid ETH amount sent to `receiver`.
    function redeemN(uint256 amount, address receiver) external returns (uint256 ethPaid) {
        ethPaid = _redeem(nToken, payoutN, amount, receiver, false);
    }

    /// @dev Shared redemption implementation. Remainders are tracked globally per
    ///      side so fragmented redemptions do not strand one floor-division dust
    ///      unit per call. The fractional benefit goes to later redeemers on the
    ///      same side, while total ETH paid remains collateral-safe.
    function _redeem(ClaimToken token, uint256 payout, uint256 amount, address receiver, bool isPToken)
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

    /// @dev Sends native ETH and reverts on zero receiver or failed transfer.
    function _sendETH(address receiver, uint256 amount) internal {
        if (receiver == address(0)) revert InvalidRecipient();
        if (amount == 0) return;

        (bool ok,) = receiver.call{value: amount}("");
        if (!ok) revert EthTransferFailed();
    }
}

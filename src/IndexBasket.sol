// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ILivePriceOracle} from "./interfaces/ILivePriceOracle.sol";

/// @title IndexBasket
/// @notice Deterministic ETH-denominated option-basket index. `levelEth(x)` is the
///         settle-at-spot value of a weighted P/N/ETH leg basket, computed purely
///         from an oracle price so it cannot be manipulated by the thin P/N pool.
contract IndexBasket is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    uint256 public constant ONE = 1e18;
    uint256 public constant MAX_LEGS = 16;
    uint256 public constant MAX_AGE_CEILING = 1 days;
    uint256 internal constant VALIDATION_STEPS = 64;

    enum LegKind {
        CAPPED, // P: min(1, K/x)
        CALL, //   N: max(0, 1 - K/x)
        ETH_SPOT //  1
    }

    struct IndexLeg {
        LegKind kind;
        uint256 strike; // 1e18; ignored for ETH_SPOT
        int256 weight; //  1e18 signed
    }

    ILivePriceOracle public oracle;
    bytes32 public feedId;
    uint256 public maxAge;
    uint256 public bandLo;
    uint256 public bandHi;
    IndexLeg[] internal _legs;

    error EmptyBasket();
    error TooManyLegs();
    error BadLeg();
    error BadBand();
    error NonPositiveLevel();
    error StalePrice();
    error ZeroPrice();
    error ZeroOracle();
    error ParamOutOfBounds();

    event LegsSet(uint256 count);
    event MaxAgeSet(uint256 maxAge);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address owner_,
        address oracle_,
        bytes32 feedId_,
        uint256 maxAge_,
        uint256 bandLo_,
        uint256 bandHi_,
        IndexLeg[] calldata legs_
    ) external initializer {
        __Ownable_init(owner_);
        if (oracle_ == address(0)) revert ZeroOracle();
        oracle = ILivePriceOracle(oracle_);
        feedId = feedId_;
        if (maxAge_ == 0 || maxAge_ > MAX_AGE_CEILING) revert ParamOutOfBounds();
        maxAge = maxAge_;
        if (bandLo_ == 0 || bandHi_ <= bandLo_) revert BadBand();
        bandLo = bandLo_;
        bandHi = bandHi_;
        _setLegs(legs_);
    }

    function legs() external view returns (IndexLeg[] memory) {
        return _legs;
    }

    function legCount() external view returns (uint256) {
        return _legs.length;
    }

    /// @notice Settle-at-spot ETH value of the basket. Reverts if non-positive.
    function levelEth(uint256 x) public view returns (uint256) {
        int256 acc;
        uint256 n = _legs.length;
        for (uint256 i; i < n; ++i) {
            IndexLeg storage leg = _legs[i];
            uint256 payoff = _ethPayoff(leg.kind, leg.strike, x);
            acc += (leg.weight * int256(payoff)) / int256(ONE);
        }
        if (acc <= 0) revert NonPositiveLevel();
        return uint256(acc);
    }

    /// @notice Level at the current fresh oracle spot.
    function currentLevel() external view returns (uint256) {
        (uint256 x, uint256 updatedAt) = oracle.getSpotValue(feedId);
        if (x == 0) revert ZeroPrice();
        if (updatedAt + maxAge < block.timestamp) revert StalePrice();
        return levelEth(x);
    }

    function setLegs(IndexLeg[] calldata legs_) external onlyOwner {
        _setLegs(legs_);
    }

    function setMaxAge(uint256 maxAge_) external onlyOwner {
        if (maxAge_ == 0 || maxAge_ > MAX_AGE_CEILING) revert ParamOutOfBounds();
        maxAge = maxAge_;
        emit MaxAgeSet(maxAge_);
    }

    function _setLegs(IndexLeg[] calldata legs_) internal {
        if (legs_.length == 0) revert EmptyBasket();
        if (legs_.length > MAX_LEGS) revert TooManyLegs();
        delete _legs;
        for (uint256 i; i < legs_.length; ++i) {
            IndexLeg calldata leg = legs_[i];
            if (leg.weight == 0) revert BadLeg();
            if (leg.kind != LegKind.ETH_SPOT && leg.strike == 0) revert BadLeg();
            _legs.push(leg);
        }
        _validateBand();
        emit LegsSet(legs_.length);
    }

    /// @dev Samples the level on a grid across [bandLo, bandHi]; reverts NonPositiveLevel
    ///      (inside levelEth) if the basket is ever non-positive in the tradeable band.
    function _validateBand() internal view {
        uint256 span = bandHi - bandLo;
        for (uint256 i; i <= VALIDATION_STEPS; ++i) {
            levelEth(bandLo + (span * i) / VALIDATION_STEPS);
        }
    }

    function _ethPayoff(LegKind kind, uint256 strike, uint256 x) internal pure returns (uint256) {
        if (kind == LegKind.ETH_SPOT) return ONE;
        if (kind == LegKind.CAPPED) return strike >= x ? ONE : (strike * ONE) / x;
        // CALL
        return strike >= x ? 0 : ONE - (strike * ONE) / x;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}

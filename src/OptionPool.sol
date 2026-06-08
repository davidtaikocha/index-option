// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {OptionSeries} from "./OptionSeries.sol";
import {ClaimToken} from "./ClaimToken.sol";

/// @title OptionPool
/// @notice Set-aware constant-product AMM for one OptionSeries. Holds only P and N
///         as reserves; ETH is transient (split on buys/funds, combine on sells).
contract OptionPool is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuard {
    uint256 public constant ONE = 1e18;
    uint256 public constant BPS = 10_000;
    uint256 public constant MAX_FEE_BPS = 100;

    OptionSeries public series;
    ClaimToken public pToken;
    ClaimToken public nToken;

    uint256 public reserveP;
    uint256 public reserveN;
    uint256 public feeBps;

    uint256 public totalShares;
    mapping(address => uint256) public sharesOf;

    error ZeroAmount();
    error InvalidPrice();
    error PoolFrozen();
    error InsufficientOutput();
    error InsufficientShares();
    error FeeTooHigh();
    error EthTransferFailed();

    event Funded(address indexed funder, uint256 ethIn, uint256 addedP, uint256 addedN, uint256 shares);
    event Withdrawn(address indexed lp, uint256 shares, uint256 outP, uint256 outN);
    event Bought(address indexed buyer, bool isP, uint256 ethIn, uint256 amountOut);
    event Sold(address indexed seller, bool isP, uint256 amountIn, uint256 ethOut);
    event SharesTransfer(address indexed from, address indexed to, uint256 amount);
    event FeeSet(uint256 feeBps);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address series_, address owner_) external initializer {
        __Ownable_init(owner_);
        series = OptionSeries(payable(series_));
        pToken = series.pToken();
        nToken = series.nToken();
        feeBps = 30;
    }

    receive() external payable {}

    modifier notFrozen() {
        if (series.settled()) revert PoolFrozen();
        _;
    }

    // --------------------------------------------------------------------- //
    // Liquidity
    // --------------------------------------------------------------------- //

    /// @notice Add liquidity with ETH. `priceP` (1e18) sets the start price for the
    ///         first funder and is ignored afterwards.
    function fund(uint256 priceP) external payable notFrozen nonReentrant returns (uint256 sharesMinted) {
        uint256 e = msg.value;
        if (e == 0) revert ZeroAmount();

        series.split{value: e}(address(this));

        uint256 addP;
        uint256 addN;
        if (totalShares == 0) {
            if (priceP == 0 || priceP >= ONE) revert InvalidPrice();
            if (priceP <= ONE / 2) {
                addP = e;
                addN = (e * priceP) / (ONE - priceP);
            } else {
                addN = e;
                addP = (e * (ONE - priceP)) / priceP;
            }
            sharesMinted = e;
        } else {
            if (reserveP >= reserveN) {
                addP = e;
                addN = (e * reserveN) / reserveP;
                sharesMinted = (totalShares * e) / reserveP;
            } else {
                addN = e;
                addP = (e * reserveP) / reserveN;
                sharesMinted = (totalShares * e) / reserveN;
            }
        }

        if (sharesMinted == 0) revert ZeroAmount();

        reserveP += addP;
        reserveN += addN;
        totalShares += sharesMinted;
        sharesOf[msg.sender] += sharesMinted;

        if (e > addP) pToken.transfer(msg.sender, e - addP);
        if (e > addN) nToken.transfer(msg.sender, e - addN);

        emit Funded(msg.sender, e, addP, addN, sharesMinted);
    }

    /// @notice Burn shares for pro-rata raw P and N. Always available (even settled).
    function withdraw(uint256 shareAmount) external nonReentrant returns (uint256 outP, uint256 outN) {
        if (shareAmount == 0) revert ZeroAmount();
        if (sharesOf[msg.sender] < shareAmount) revert InsufficientShares();

        outP = (reserveP * shareAmount) / totalShares;
        outN = (reserveN * shareAmount) / totalShares;

        sharesOf[msg.sender] -= shareAmount;
        totalShares -= shareAmount;
        reserveP -= outP;
        reserveN -= outN;

        pToken.transfer(msg.sender, outP);
        nToken.transfer(msg.sender, outN);

        emit Withdrawn(msg.sender, shareAmount, outP, outN);
    }

    function transferShares(address to, uint256 amount) external returns (bool) {
        if (sharesOf[msg.sender] < amount) revert InsufficientShares();
        sharesOf[msg.sender] -= amount;
        sharesOf[to] += amount;
        emit SharesTransfer(msg.sender, to, amount);
        return true;
    }

    // --------------------------------------------------------------------- //
    // Swaps
    // --------------------------------------------------------------------- //

    function buyP(uint256 minOut) external payable notFrozen nonReentrant returns (uint256 outP) {
        outP = _buy(true, minOut);
    }

    function buyN(uint256 minOut) external payable notFrozen nonReentrant returns (uint256 outN) {
        outN = _buy(false, minOut);
    }

    function sellP(uint256 inP, uint256 minEthOut) external notFrozen nonReentrant returns (uint256 ethOut) {
        ethOut = _sell(true, inP, minEthOut);
    }

    function sellN(uint256 inN, uint256 minEthOut) external notFrozen nonReentrant returns (uint256 ethOut) {
        ethOut = _sell(false, inN, minEthOut);
    }

    function _buy(bool isP, uint256 minOut) internal returns (uint256 outAmt) {
        uint256 e = msg.value;
        if (e == 0) revert ZeroAmount();

        (uint256 rOut, uint256 rOther) = isP ? (reserveP, reserveN) : (reserveN, reserveP);
        outAmt = _buyAmount(rOut, rOther, e);
        if (outAmt < minOut) revert InsufficientOutput();

        series.split{value: e}(address(this));

        if (isP) {
            reserveP = reserveP + e - outAmt;
            reserveN += e;
            pToken.transfer(msg.sender, outAmt);
        } else {
            reserveN = reserveN + e - outAmt;
            reserveP += e;
            nToken.transfer(msg.sender, outAmt);
        }

        emit Bought(msg.sender, isP, e, outAmt);
    }

    function _sell(bool isP, uint256 inAmt, uint256 minEthOut) internal returns (uint256 ethOut) {
        if (inAmt == 0) revert ZeroAmount();

        (uint256 rAdd, uint256 rOther) = isP ? (reserveP, reserveN) : (reserveN, reserveP);
        ethOut = _sellAmount(rAdd, rOther, inAmt);
        if (ethOut < minEthOut) revert InsufficientOutput();

        ClaimToken inToken = isP ? pToken : nToken;
        inToken.transferFrom(msg.sender, address(this), inAmt);

        if (isP) {
            reserveP = reserveP + inAmt - ethOut;
            reserveN -= ethOut;
        } else {
            reserveN = reserveN + inAmt - ethOut;
            reserveP -= ethOut;
        }

        series.combine(ethOut, msg.sender);

        emit Sold(msg.sender, isP, inAmt, ethOut);
    }

    // --------------------------------------------------------------------- //
    // Pricing (pure)
    // --------------------------------------------------------------------- //

    /// @dev outcome bought with `eth`: a = fee-discounted input added to the other side.
    function _buyAmount(uint256 rOut, uint256 rOther, uint256 eth) internal view returns (uint256) {
        uint256 a = (eth * (BPS - feeBps)) / BPS;
        uint256 ending = Math.ceilDiv(rOut * rOther, rOther + a);
        return rOut + a - ending;
    }

    /// @dev sell `inAmt` of the add side: r solves (rAdd+inEff-r)(rOther-r)=k (smaller root).
    function _sellAmount(uint256 rAdd, uint256 rOther, uint256 inAmt) internal view returns (uint256) {
        uint256 inEff = (inAmt * (BPS - feeBps)) / BPS;
        uint256 a = rAdd + inEff;
        uint256 sum = a + rOther;
        uint256 disc = sum * sum - 4 * rOther * inEff;
        return (sum - Math.sqrt(disc)) / 2;
    }

    function getReserves() external view returns (uint256, uint256) {
        return (reserveP, reserveN);
    }

    function spotPriceP() external view returns (uint256) {
        uint256 total = reserveP + reserveN;
        if (total == 0) return 0;
        return (reserveN * ONE) / total;
    }

    function quoteBuyP(uint256 eth) external view returns (uint256) {
        return _buyAmount(reserveP, reserveN, eth);
    }

    function quoteBuyN(uint256 eth) external view returns (uint256) {
        return _buyAmount(reserveN, reserveP, eth);
    }

    function quoteSellP(uint256 inP) external view returns (uint256) {
        return _sellAmount(reserveP, reserveN, inP);
    }

    function quoteSellN(uint256 inN) external view returns (uint256) {
        return _sellAmount(reserveN, reserveP, inN);
    }

    // --------------------------------------------------------------------- //
    // Admin
    // --------------------------------------------------------------------- //

    function setFee(uint256 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_FEE_BPS) revert FeeTooHigh();
        feeBps = newFeeBps;
        emit FeeSet(newFeeBps);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}

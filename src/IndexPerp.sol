// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {FundingMath} from "./FundingMath.sol";
import {IndexBasket} from "./IndexBasket.sol";
import {PerpVault} from "./PerpVault.sol";
import {InsuranceFund} from "./InsuranceFund.sol";

/// @title IndexPerp
/// @notice ETH-margined perpetual on an option-basket index, oracle-execution,
///         pooled LP vault counterparty. Fills at IndexBasket.currentLevel().
contract IndexPerp is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuard {
    uint256 public constant ONE = 1e18;
    uint256 public constant BPS = 10_000;
    uint256 public constant MAX_LEVERAGE_CEILING = 100e18;
    uint256 public constant MAX_FEE_BPS = 100; // 1%
    uint256 public constant MAX_MM_BPS = 5_000; // 50%
    uint256 public constant MAX_LIQ_PENALTY_BPS = 2_000; // 20%
    uint256 public constant MAX_BORROW_BASE = 1e15; // per-second, 1e18-scaled
    uint256 public constant MAX_FUND_K = 1e15;

    IndexBasket public basket;
    PerpVault public vault;
    InsuranceFund public insurance;

    uint256 public borrowCum; // monotonic
    int256 public fundingCum;
    uint64 public lastPoke;
    uint256 public longOI;
    uint256 public shortOI;

    uint256 public maxLeverage;
    uint256 public openFeeBps;
    uint256 public closeFeeBps;
    uint256 public borrowBase;
    uint256 public fundK;
    uint256 public mmBps;
    uint256 public liqPenaltyBps;

    struct Position {
        address owner;
        bool isLong;
        uint256 units;
        uint256 entryLevel;
        uint256 marginEth;
        uint256 entryBorrowCum;
        int256 entryFundingCum;
        uint64 openedAt;
    }

    mapping(uint256 id => Position) public positions;
    uint256 public nextId;

    struct InitParams {
        address owner;
        address basket;
        address vault;
        address insurance;
        uint256 maxLeverage;
        uint256 openFeeBps;
        uint256 closeFeeBps;
        uint256 borrowBase;
        uint256 fundK;
        uint256 mmBps;
        uint256 liqPenaltyBps;
    }

    error ZeroMargin();
    error LeverageTooHigh();
    error SlippageExceeded();
    error NotOwner();
    error PositionClosed();
    error NotLiquidatable();
    error ParamOutOfBounds();
    error EthTransferFailed();

    event Opened(uint256 indexed id, address indexed owner, bool isLong, uint256 units, uint256 entryLevel, uint256 marginEth);
    event Closed(uint256 indexed id, int256 pnl, uint256 payout);
    event MarginAdded(uint256 indexed id, uint256 amount);
    event Liquidated(uint256 indexed id, address indexed keeper, uint256 penalty);
    event Poked(uint256 borrowCum, int256 fundingCum);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    receive() external payable {} // accepts vault.payProfit(address(this)) during liquidation

    function initialize(InitParams calldata p) external initializer {
        __Ownable_init(p.owner);
        basket = IndexBasket(p.basket);
        vault = PerpVault(payable(p.vault));
        insurance = InsuranceFund(payable(p.insurance));
        _setParams(p.maxLeverage, p.openFeeBps, p.closeFeeBps, p.borrowBase, p.fundK, p.mmBps, p.liqPenaltyBps);
        lastPoke = uint64(block.timestamp);
        nextId = 1;
    }

    // ----------------------------------------------------------------- //
    // Accrual
    // ----------------------------------------------------------------- //

    function _poke() internal {
        uint256 dt = block.timestamp - lastPoke;
        if (dt == 0) return;
        borrowCum += FundingMath.borrowDelta(borrowBase, vault.reserved(), vault.totalAssets(), dt);
        fundingCum += FundingMath.fundingDelta(fundK, longOI, shortOI, dt);
        lastPoke = uint64(block.timestamp);
        emit Poked(borrowCum, fundingCum);
    }

    // ----------------------------------------------------------------- //
    // Open
    // ----------------------------------------------------------------- //

    function open(bool isLong, uint256 leverage, uint256 limitLevel)
        external
        payable
        nonReentrant
        returns (uint256 id)
    {
        if (msg.value == 0) revert ZeroMargin();
        if (leverage == 0 || leverage > maxLeverage) revert LeverageTooHigh();
        _poke();
        uint256 level = basket.currentLevel();
        if (isLong ? level > limitLevel : level < limitLevel) revert SlippageExceeded();

        uint256 notional = (leverage * msg.value) / ONE;
        uint256 units = (leverage * msg.value) / level;
        uint256 openFee = (notional * openFeeBps) / BPS;
        uint256 margin = msg.value - openFee;

        if (openFee > 0) vault.takeLoss{value: openFee}();
        vault.reserve(notional);

        if (isLong) longOI += notional;
        else shortOI += notional;

        id = nextId++;
        positions[id] = Position({
            owner: msg.sender,
            isLong: isLong,
            units: units,
            entryLevel: level,
            marginEth: margin,
            entryBorrowCum: borrowCum,
            entryFundingCum: fundingCum,
            openedAt: uint64(block.timestamp)
        });
        emit Opened(id, msg.sender, isLong, units, level, margin);
    }

    // ----------------------------------------------------------------- //
    // Close / margin
    // ----------------------------------------------------------------- //

    function close(uint256 id, uint256 limitLevel) external nonReentrant returns (int256 pnl) {
        Position memory pos = positions[id];
        if (pos.owner == address(0)) revert PositionClosed();
        if (pos.owner != msg.sender) revert NotOwner();
        _poke();
        uint256 level = basket.currentLevel();
        if (pos.isLong ? level < limitLevel : level > limitLevel) revert SlippageExceeded();

        (int256 pnl_, uint256 borrowOwed, int256 fundOwed, uint256 notional) = _settleMath(pos, level);
        pnl = pnl_;
        uint256 closeFee = (((pos.units * level) / ONE) * closeFeeBps) / BPS;

        int256 settle =
            int256(pos.marginEth) + pnl - int256(borrowOwed) - fundOwed - int256(closeFee);
        int256 vaultDelta = -pnl + int256(borrowOwed) + fundOwed + int256(closeFee);

        if (pos.isLong) longOI -= notional;
        else shortOI -= notional;
        vault.release(notional);
        delete positions[id];

        uint256 payout = _disburseTo(pos.owner, pos.marginEth, settle, vaultDelta);
        emit Closed(id, pnl, payout);
    }

    function addMargin(uint256 id) external payable nonReentrant {
        Position storage pos = positions[id];
        if (pos.owner == address(0)) revert PositionClosed();
        if (pos.owner != msg.sender) revert NotOwner();
        if (msg.value == 0) revert ZeroMargin();
        pos.marginEth += msg.value;
        emit MarginAdded(id, msg.value);
    }

    /// @notice Current equity and notional of a position at `level`.
    /// @dev View — does not call `_poke()`, so accumulators are as of the last poke;
    ///      returned equity slightly overstates true equity (borrow/funding underestimated).
    function equityOf(uint256 id, uint256 level) public view returns (int256 equity, uint256 notional) {
        Position memory pos = positions[id];
        (int256 pnl, uint256 borrowOwed, int256 fundOwed, uint256 n) = _settleMath(pos, level);
        notional = n;
        equity = int256(pos.marginEth) + pnl - int256(borrowOwed) - fundOwed;
    }

    function liquidate(uint256 id) external nonReentrant returns (uint256 charged) {
        Position memory pos = positions[id];
        if (pos.owner == address(0)) revert PositionClosed();
        _poke();
        uint256 level = basket.currentLevel();

        uint256 notional;
        int256 settle;
        int256 vaultDelta;
        // Scoped to drop the settlement locals before the payout section (keeps the
        // function within the EVM stack limit under default codegen — no via-IR needed).
        {
            (int256 pnl, uint256 borrowOwed, int256 fundOwed, uint256 n) = _settleMath(pos, level);
            int256 equity = int256(pos.marginEth) + pnl - int256(borrowOwed) - fundOwed;
            if (equity >= int256((n * mmBps) / BPS)) revert NotLiquidatable();
            notional = n;
            settle = equity; // no close fee on liquidation; penalty taken instead
            vaultDelta = -pnl + int256(borrowOwed) + fundOwed;
        }

        if (pos.isLong) longOI -= notional;
        else shortOI -= notional;
        vault.release(notional);
        delete positions[id];

        charged = _settleLiquidationPayout(pos.owner, pos.marginEth, settle, vaultDelta, (notional * liqPenaltyBps) / BPS);

        emit Liquidated(id, msg.sender, charged);
    }

    /// @dev Pulls the trader's gross equity into this contract, skims the penalty
    ///      (capped at the available gross), splits it keeper/insurance, and returns
    ///      any remainder to the trader. Returns the penalty actually charged.
    function _settleLiquidationPayout(
        address posOwner,
        uint256 margin,
        int256 settle,
        int256 vaultDelta,
        uint256 penalty
    ) internal returns (uint256 charged) {
        uint256 gross = _disburseTo(address(this), margin, settle, vaultDelta);
        charged = penalty > gross ? gross : penalty;
        uint256 keeperReward = charged / 2;
        uint256 insCut = charged - keeperReward;
        if (keeperReward > 0) _sendEth(msg.sender, keeperReward);
        if (insCut > 0) _sendEth(address(insurance), insCut);
        uint256 traderGets = gross - charged;
        if (traderGets > 0) _sendEth(posOwner, traderGets);
    }

    // ----------------------------------------------------------------- //
    // Settlement math + disbursement
    // ----------------------------------------------------------------- //

    function _settleMath(Position memory pos, uint256 level)
        internal
        view
        returns (int256 pnl, uint256 borrowOwed, int256 fundOwed, uint256 notional)
    {
        notional = (pos.units * pos.entryLevel) / ONE;
        uint256 markValue = (pos.units * level) / ONE;
        pnl = pos.isLong ? int256(markValue) - int256(notional) : int256(notional) - int256(markValue);
        borrowOwed = (notional * (borrowCum - pos.entryBorrowCum)) / ONE;
        int256 fundDiff = fundingCum - pos.entryFundingCum;
        int256 raw = (int256(notional) * fundDiff) / int256(ONE);
        fundOwed = pos.isLong ? raw : -raw;
    }

    /// @dev Routes ETH for a closing position. `recipient == address(this)` keeps the
    ///      trader payout inside the perp (used by liquidation to skim a penalty).
    ///      Returns the gross ETH owed to the trader before any penalty.
    function _disburseTo(address recipient, uint256 margin, int256 settle, int256 vaultDelta)
        internal
        returns (uint256 grossToRecipient)
    {
        if (settle < 0) {
            if (margin > 0) vault.takeLoss{value: margin}();
            insurance.coverShortfall(address(vault), uint256(-settle));
            return 0;
        }
        if (vaultDelta >= 0) {
            uint256 vd = uint256(vaultDelta);
            if (vd > 0) vault.takeLoss{value: vd}();
            grossToRecipient = margin - vd; // == uint256(settle)
            if (recipient != address(this)) _sendEth(recipient, grossToRecipient);
        } else {
            // Trader profit owed by the vault. Pay what the vault holds and cover any
            // remainder from the insurance fund (mirroring the loss path) so a winning
            // trader is never stranded by a temporarily under-funded vault. Any amount
            // still uncovered surfaces as BadDebt inside the insurance fund, never silently.
            uint256 owed = uint256(-vaultDelta);
            uint256 vaultBal = vault.totalAssets();
            uint256 fromVault = owed > vaultBal ? vaultBal : owed;
            if (fromVault > 0) vault.payProfit(address(this), fromVault);
            uint256 covered;
            if (owed > fromVault) covered = insurance.coverShortfall(address(this), owed - fromVault);
            grossToRecipient = margin + fromVault + covered;
            if (recipient != address(this)) _sendEth(recipient, grossToRecipient);
        }
    }

    function notionalOf(uint256 id) external view returns (uint256) {
        Position storage pos = positions[id];
        return (pos.units * pos.entryLevel) / ONE;
    }

    // ----------------------------------------------------------------- //
    // Params / upgrade
    // ----------------------------------------------------------------- //

    function setParams(
        uint256 maxLeverage_,
        uint256 openFeeBps_,
        uint256 closeFeeBps_,
        uint256 borrowBase_,
        uint256 fundK_,
        uint256 mmBps_,
        uint256 liqPenaltyBps_
    ) external onlyOwner {
        _setParams(maxLeverage_, openFeeBps_, closeFeeBps_, borrowBase_, fundK_, mmBps_, liqPenaltyBps_);
    }

    function _setParams(
        uint256 maxLeverage_,
        uint256 openFeeBps_,
        uint256 closeFeeBps_,
        uint256 borrowBase_,
        uint256 fundK_,
        uint256 mmBps_,
        uint256 liqPenaltyBps_
    ) internal {
        if (maxLeverage_ == 0 || maxLeverage_ > MAX_LEVERAGE_CEILING) revert ParamOutOfBounds();
        if (openFeeBps_ > MAX_FEE_BPS || closeFeeBps_ > MAX_FEE_BPS) revert ParamOutOfBounds();
        if (borrowBase_ > MAX_BORROW_BASE || fundK_ > MAX_FUND_K) revert ParamOutOfBounds();
        if (mmBps_ == 0 || mmBps_ > MAX_MM_BPS) revert ParamOutOfBounds();
        if (liqPenaltyBps_ > MAX_LIQ_PENALTY_BPS) revert ParamOutOfBounds();
        maxLeverage = maxLeverage_;
        openFeeBps = openFeeBps_;
        closeFeeBps = closeFeeBps_;
        borrowBase = borrowBase_;
        fundK = fundK_;
        mmBps = mmBps_;
        liqPenaltyBps = liqPenaltyBps_;
    }

    function _sendEth(address to, uint256 amount) internal {
        if (amount == 0) return;
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert EthTransferFailed();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}

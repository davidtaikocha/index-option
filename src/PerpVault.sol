// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title PerpVault
/// @notice Pooled ETH LP house and counterparty to all perp positions. Holds LP
///         capital plus realized fees/PnL; trader margins live in IndexPerp.
contract PerpVault is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuard {
    uint256 public constant BPS = 10_000;
    uint256 public constant MAX_UTIL_CEILING = 10_000;

    address public perp;
    uint256 public totalShares;
    mapping(address lp => uint256 shares) public sharesOf;
    uint256 public reserved;
    uint256 public maxUtilBps;

    error ZeroAmount();
    error ZeroAddress();
    error OnlyPerp();
    error InsufficientShares();
    error InsufficientFreeAssets();
    error UtilizationExceeded();
    error EthTransferFailed();
    error ParamOutOfBounds();

    event Deposited(address indexed lp, uint256 ethIn, uint256 shares);
    event Withdrawn(address indexed lp, uint256 shares, uint256 ethOut);
    event Reserved(uint256 amount, uint256 totalReserved);
    event Released(uint256 amount, uint256 totalReserved);
    event ProfitPaid(address indexed to, uint256 amount);
    event LossTaken(uint256 amount);
    event PerpSet(address perp);
    event MaxUtilSet(uint256 maxUtilBps);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner_, uint256 maxUtilBps_) external initializer {
        if (owner_ == address(0)) revert ZeroAddress();
        if (maxUtilBps_ == 0 || maxUtilBps_ > MAX_UTIL_CEILING) revert ParamOutOfBounds();
        __Ownable_init(owner_);
        maxUtilBps = maxUtilBps_;
    }

    /// @dev Recapitalization (e.g. insurance top-up) raises share price.
    receive() external payable {}

    modifier onlyPerp() {
        if (msg.sender != perp) revert OnlyPerp();
        _;
    }

    function setPerp(address perp_) external onlyOwner {
        if (perp_ == address(0)) revert ZeroAddress();
        perp = perp_;
        emit PerpSet(perp_);
    }

    function totalAssets() public view returns (uint256) {
        return address(this).balance;
    }

    function freeAssets() public view returns (uint256) {
        uint256 bal = address(this).balance;
        return bal > reserved ? bal - reserved : 0;
    }

    function deposit() external payable nonReentrant returns (uint256 shares) {
        if (msg.value == 0) revert ZeroAmount();
        uint256 balBefore = address(this).balance - msg.value;
        // balBefore == 0 with shares outstanding (vault fully drained via payProfit)
        // resets pricing to 1:1 for the recapitalizing deposit, avoiding a div-by-zero panic.
        shares = (totalShares == 0 || balBefore == 0) ? msg.value : (msg.value * totalShares) / balBefore;
        if (shares == 0) revert ZeroAmount();
        totalShares += shares;
        sharesOf[msg.sender] += shares;
        emit Deposited(msg.sender, msg.value, shares);
    }

    function withdraw(uint256 shares) external nonReentrant returns (uint256 ethOut) {
        if (shares == 0) revert ZeroAmount();
        if (sharesOf[msg.sender] < shares) revert InsufficientShares();
        ethOut = (shares * address(this).balance) / totalShares;
        if (ethOut > freeAssets()) revert InsufficientFreeAssets();
        sharesOf[msg.sender] -= shares;
        totalShares -= shares;
        (bool ok,) = msg.sender.call{value: ethOut}("");
        if (!ok) revert EthTransferFailed();
        emit Withdrawn(msg.sender, shares, ethOut);
    }

    function reserve(uint256 amount) external onlyPerp {
        uint256 newReserved = reserved + amount;
        if (newReserved > (address(this).balance * maxUtilBps) / BPS) revert UtilizationExceeded();
        reserved = newReserved;
        emit Reserved(amount, newReserved);
    }

    function release(uint256 amount) external onlyPerp {
        reserved = amount >= reserved ? 0 : reserved - amount;
        emit Released(amount, reserved);
    }

    function payProfit(address to, uint256 amount) external onlyPerp nonReentrant {
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert EthTransferFailed();
        emit ProfitPaid(to, amount);
    }

    function takeLoss() external payable onlyPerp {
        emit LossTaken(msg.value);
    }

    function setMaxUtilBps(uint256 v) external onlyOwner {
        if (v == 0 || v > MAX_UTIL_CEILING) revert ParamOutOfBounds();
        maxUtilBps = v;
        emit MaxUtilSet(v);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title InsuranceFund
/// @notice ETH backstop. Only the perp may draw, and only to cover settlement
///         shortfalls; uncovered amounts are surfaced via BadDebt, never silent.
contract InsuranceFund is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuard {
    address public perp;

    error OnlyPerp();
    error ZeroAddress();
    error EthTransferFailed();

    event Deposited(address indexed from, uint256 amount);
    event PerpSet(address perp);
    event ShortfallCovered(address indexed to, uint256 requested, uint256 paid);
    event BadDebt(uint256 uncovered);
    event Withdrawn(address indexed to, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner_) external initializer {
        if (owner_ == address(0)) revert ZeroAddress();
        __Ownable_init(owner_);
    }

    receive() external payable {
        emit Deposited(msg.sender, msg.value);
    }

    function deposit() external payable {
        emit Deposited(msg.sender, msg.value);
    }

    function setPerp(address perp_) external onlyOwner {
        if (perp_ == address(0)) revert ZeroAddress();
        perp = perp_;
        emit PerpSet(perp_);
    }

    function coverShortfall(address to, uint256 amount) external nonReentrant returns (uint256 paid) {
        if (msg.sender != perp) revert OnlyPerp();
        uint256 bal = address(this).balance;
        paid = amount > bal ? bal : amount;
        if (paid > 0) {
            (bool ok,) = to.call{value: paid}("");
            if (!ok) revert EthTransferFailed();
        }
        emit ShortfallCovered(to, amount, paid);
        if (amount > paid) emit BadDebt(amount - paid);
    }

    function withdraw(uint256 amount, address to) external onlyOwner nonReentrant {
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert EthTransferFailed();
        emit Withdrawn(to, amount);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}

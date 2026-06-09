// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ILivePriceOracle} from "./interfaces/ILivePriceOracle.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";

/// @title PushOracle
/// @notice Keeper-pushed ETH/USDC spot feed plus per-series resolution, so it can
///         replace the EOA oracle for OptionSeries settlement too.
contract PushOracle is Initializable, OwnableUpgradeable, UUPSUpgradeable, ILivePriceOracle, IPriceOracle {
    struct Feed {
        uint256 value;
        uint256 updatedAt;
    }

    struct Resolution {
        bool resolved;
        uint256 value;
    }

    address public keeper;
    mapping(bytes32 feedId => Feed) internal feeds;
    mapping(address series => Resolution) internal resolutions;

    error Unauthorized();
    error ZeroKeeper();
    error ZeroPrice();

    event PricePushed(bytes32 indexed feedId, uint256 value, uint256 updatedAt);
    event SeriesResolved(address indexed series, uint256 value);
    event KeeperSet(address keeper);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner_, address keeper_) external initializer {
        if (owner_ == address(0)) revert Unauthorized();
        if (keeper_ == address(0)) revert ZeroKeeper();
        __Ownable_init(owner_);
        keeper = keeper_;
    }

    modifier onlyKeeper() {
        if (msg.sender != keeper && msg.sender != owner()) revert Unauthorized();
        _;
    }

    function pushPrice(bytes32 feedId, uint256 value) external onlyKeeper {
        if (value == 0) revert ZeroPrice();
        feeds[feedId] = Feed({value: value, updatedAt: block.timestamp});
        emit PricePushed(feedId, value, block.timestamp);
    }

    function getSpotValue(bytes32 feedId) external view returns (uint256 value, uint256 updatedAt) {
        Feed storage f = feeds[feedId];
        return (f.value, f.updatedAt);
    }

    function resolveSeries(address series, uint256 value) external onlyKeeper {
        if (value == 0) revert ZeroPrice();
        resolutions[series] = Resolution({resolved: true, value: value});
        emit SeriesResolved(series, value);
    }

    function getResolvedValue(address series) external view returns (bool resolved, uint256 value) {
        Resolution storage r = resolutions[series];
        return (r.resolved, r.value);
    }

    function setKeeper(address keeper_) external onlyOwner {
        if (keeper_ == address(0)) revert ZeroKeeper();
        keeper = keeper_;
        emit KeeperSet(keeper_);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}

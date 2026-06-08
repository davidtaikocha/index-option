// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OptionPool} from "./OptionPool.sol";
import {OptionSeries} from "./OptionSeries.sol";

/// @title OptionPoolFactory
/// @notice Deploys one canonical OptionPool proxy per OptionSeries.
contract OptionPoolFactory is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    address public poolImplementation;
    mapping(address series => address pool) public poolOf;

    error ZeroUpgradeAdmin();
    error ZeroPoolImplementation();
    error ZeroSeries();
    error PoolExists();

    event PoolCreated(address indexed series, address pool, address pToken, address nToken);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address upgradeAdmin_, address poolImplementation_) external initializer {
        if (upgradeAdmin_ == address(0)) revert ZeroUpgradeAdmin();
        if (poolImplementation_ == address(0)) revert ZeroPoolImplementation();
        __Ownable_init(upgradeAdmin_);
        poolImplementation = poolImplementation_;
    }

    function createPool(address series) external returns (address pool) {
        if (series == address(0)) revert ZeroSeries();
        if (poolOf[series] != address(0)) revert PoolExists();

        bytes memory initData = abi.encodeCall(OptionPool.initialize, (series, owner()));
        ERC1967Proxy proxy = new ERC1967Proxy(poolImplementation, initData);
        pool = address(proxy);
        poolOf[series] = pool;

        OptionSeries s = OptionSeries(payable(series));
        emit PoolCreated(series, pool, address(s.pToken()), address(s.nToken()));
    }

    function setPoolImplementation(address newImplementation) external onlyOwner {
        if (newImplementation == address(0)) revert ZeroPoolImplementation();
        poolImplementation = newImplementation;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}

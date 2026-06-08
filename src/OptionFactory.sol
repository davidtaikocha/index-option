// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OptionSeries} from "./OptionSeries.sol";

/// @title OptionFactory
/// @notice Deploys self-contained ETH/USDC option series contracts.
/// @dev Each deployed `OptionSeries` proxy owns its own ETH collateral and P/N
///      claim tokens, so no global factory accounting is required.
contract OptionFactory is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    /// @notice Current implementation used for newly created option series proxies.
    address public seriesImplementation;

    /// @notice Upgrade admin address cannot be zero.
    error ZeroUpgradeAdmin();
    /// @notice Series implementation address cannot be zero.
    error ZeroSeriesImplementation();

    /// @notice Emitted after a new ETH/USDC option series and its P/N tokens are deployed.
    /// @param series Address of the newly deployed option series.
    /// @param strike 1e18 fixed-point ETH/USDC strike price.
    /// @param maturity Timestamp after which the series can be settled.
    /// @param oracle Oracle contract used by the series at settlement.
    /// @param pToken P-side claim token deployed by the series.
    /// @param nToken N-side claim token deployed by the series.
    event OptionSeriesCreated(
        address indexed series, uint256 strike, uint256 maturity, address oracle, address pToken, address nToken
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the factory proxy.
    /// @param upgradeAdmin_ Owner authorized to upgrade the factory and created series.
    /// @param seriesImplementation_ Implementation used for newly created series proxies.
    function initialize(address upgradeAdmin_, address seriesImplementation_) external initializer {
        if (upgradeAdmin_ == address(0)) revert ZeroUpgradeAdmin();
        if (seriesImplementation_ == address(0)) revert ZeroSeriesImplementation();

        __Ownable_init(upgradeAdmin_);

        seriesImplementation = seriesImplementation_;
    }

    /// @notice Deploys a new ETH/USDC option series and returns its address.
    /// @dev Initializer validation is delegated to `OptionSeries`; validation
    ///      errors such as zero strike or zero oracle propagate unchanged.
    /// @param strike 1e18 fixed-point ETH/USDC strike price.
    /// @param maturity Timestamp after which settlement is allowed.
    /// @param oracle Oracle contract implementing `IPriceOracle`.
    /// @return seriesAddress Address of the newly deployed option series.
    function createSeries(uint256 strike, uint256 maturity, address oracle) external returns (address seriesAddress) {
        bytes memory initData = abi.encodeCall(OptionSeries.initialize, (strike, maturity, oracle, owner()));
        ERC1967Proxy proxy = new ERC1967Proxy(seriesImplementation, initData);
        seriesAddress = address(proxy);
        OptionSeries series = OptionSeries(seriesAddress);

        emit OptionSeriesCreated(
            seriesAddress, strike, maturity, oracle, address(series.pToken()), address(series.nToken())
        );
    }

    /// @notice Updates the implementation used for future option series proxies.
    /// @param newImplementation New `OptionSeries` implementation address.
    function setSeriesImplementation(address newImplementation) external onlyOwner {
        if (newImplementation == address(0)) revert ZeroSeriesImplementation();
        seriesImplementation = newImplementation;
    }

    /// @dev Restricts UUPS upgrades to the factory owner.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}

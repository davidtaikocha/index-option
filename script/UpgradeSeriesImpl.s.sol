// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {OptionFactory} from "../src/OptionFactory.sol";
import {OptionSeries} from "../src/OptionSeries.sol";

/// @notice Deploys a new OptionSeries implementation (with the relaxed split) and
///         points the existing factory at it, so newly created series get the relax.
contract UpgradeSeriesImpl is Script {
    function run() external returns (OptionSeries newImplementation) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address factoryAddress = vm.envAddress("OPTION_FACTORY");

        vm.startBroadcast(deployerPrivateKey);
        newImplementation = new OptionSeries();
        OptionFactory(factoryAddress).setSeriesImplementation(address(newImplementation));
        vm.stopBroadcast();

        console2.log("NEW_SERIES_IMPLEMENTATION", address(newImplementation));
    }
}

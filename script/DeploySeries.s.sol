// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {OptionFactory} from "../src/OptionFactory.sol";
import {OptionSeries} from "../src/OptionSeries.sol";

/// @notice Creates a new P/N option series through an existing factory proxy.
contract DeploySeries is Script {
    function run() external returns (OptionSeries series) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address factoryAddress = vm.envAddress("OPTION_FACTORY");
        uint256 strike = vm.envUint("SERIES_STRIKE");
        uint256 maturity = vm.envUint("SERIES_MATURITY");
        address oracle = vm.envAddress("SERIES_ORACLE");

        OptionFactory factory = OptionFactory(factoryAddress);

        vm.startBroadcast(deployerPrivateKey);
        address seriesAddress = factory.createSeries(strike, maturity, oracle);
        vm.stopBroadcast();

        series = OptionSeries(seriesAddress);

        console2.log("OPTION_FACTORY", factoryAddress);
        console2.log("SERIES_PROXY", seriesAddress);
        console2.log("P_TOKEN", address(series.pToken()));
        console2.log("N_TOKEN", address(series.nToken()));
    }
}

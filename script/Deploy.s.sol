// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Script, console2} from "forge-std/Script.sol";
import {OptionFactory} from "../src/OptionFactory.sol";
import {OptionSeries} from "../src/OptionSeries.sol";

/// @notice Deploys the OptionSeries implementation, OptionFactory implementation,
///         and the UUPS factory proxy.
contract Deploy is Script {
    function run()
        external
        returns (OptionSeries seriesImplementation, OptionFactory factoryImplementation, OptionFactory factory)
    {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address upgradeAdmin = vm.envOr("UPGRADE_ADMIN", address(0));
        if (upgradeAdmin == address(0)) {
            upgradeAdmin = vm.addr(deployerPrivateKey);
        }

        vm.startBroadcast(deployerPrivateKey);

        seriesImplementation = new OptionSeries();
        factoryImplementation = new OptionFactory();

        bytes memory initData = abi.encodeCall(OptionFactory.initialize, (upgradeAdmin, address(seriesImplementation)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(factoryImplementation), initData);
        factory = OptionFactory(address(proxy));

        vm.stopBroadcast();

        console2.log("UPGRADE_ADMIN", upgradeAdmin);
        console2.log("SERIES_IMPLEMENTATION", address(seriesImplementation));
        console2.log("FACTORY_IMPLEMENTATION", address(factoryImplementation));
        console2.log("FACTORY_PROXY", address(factory));
    }
}

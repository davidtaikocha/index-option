// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Script, console2} from "forge-std/Script.sol";
import {OptionPool} from "../src/OptionPool.sol";
import {OptionPoolFactory} from "../src/OptionPoolFactory.sol";

/// @notice Deploys the OptionPool implementation, OptionPoolFactory implementation,
///         and the UUPS pool-factory proxy.
contract DeployPoolFactory is Script {
    function run()
        external
        returns (OptionPool poolImplementation, OptionPoolFactory factoryImplementation, OptionPoolFactory factory)
    {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address upgradeAdmin = vm.envOr("UPGRADE_ADMIN", address(0));
        if (upgradeAdmin == address(0)) {
            upgradeAdmin = vm.addr(deployerPrivateKey);
        }

        vm.startBroadcast(deployerPrivateKey);
        poolImplementation = new OptionPool();
        factoryImplementation = new OptionPoolFactory();
        bytes memory initData =
            abi.encodeCall(OptionPoolFactory.initialize, (upgradeAdmin, address(poolImplementation)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(factoryImplementation), initData);
        factory = OptionPoolFactory(address(proxy));
        vm.stopBroadcast();

        console2.log("POOL_IMPLEMENTATION", address(poolImplementation));
        console2.log("POOL_FACTORY_IMPLEMENTATION", address(factoryImplementation));
        console2.log("POOL_FACTORY", address(factory));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Script, console2} from "forge-std/Script.sol";
import {PushOracle} from "../src/PushOracle.sol";
import {IndexBasket} from "../src/IndexBasket.sol";
import {PerpVault} from "../src/PerpVault.sol";
import {InsuranceFund} from "../src/InsuranceFund.sol";
import {IndexPerp} from "../src/IndexPerp.sol";

/// @notice Deploys and wires one full Index Perp stack with a seed CALL@2000 basket.
contract DeployIndexPerp is Script {
    bytes32 internal constant FEED = bytes32("ETHUSDC");

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address admin = vm.envOr("UPGRADE_ADMIN", vm.addr(pk));
        address keeper = vm.envOr("KEEPER", vm.addr(pk));

        vm.startBroadcast(pk);

        PushOracle oracle = PushOracle(
            address(new ERC1967Proxy(address(new PushOracle()), abi.encodeCall(PushOracle.initialize, (admin, keeper))))
        );

        IndexBasket.IndexLeg[] memory legs = new IndexBasket.IndexLeg[](1);
        legs[0] = IndexBasket.IndexLeg({kind: IndexBasket.LegKind.CALL, strike: 2000e18, weight: 1e18});
        IndexBasket basket = IndexBasket(
            address(
                new ERC1967Proxy(
                    address(new IndexBasket()),
                    abi.encodeCall(
                        IndexBasket.initialize, (admin, address(oracle), FEED, 1 hours, 2100e18, 10000e18, legs)
                    )
                )
            )
        );

        PerpVault vault = PerpVault(
            payable(address(new ERC1967Proxy(address(new PerpVault()), abi.encodeCall(PerpVault.initialize, (admin, 9000)))))
        );
        InsuranceFund insurance = InsuranceFund(
            payable(address(new ERC1967Proxy(address(new InsuranceFund()), abi.encodeCall(InsuranceFund.initialize, (admin)))))
        );

        IndexPerp.InitParams memory p = IndexPerp.InitParams({
            owner: admin,
            basket: address(basket),
            vault: address(vault),
            insurance: address(insurance),
            maxLeverage: 20e18,
            openFeeBps: 10,
            closeFeeBps: 10,
            borrowBase: 1e8,
            fundK: 1e8,
            mmBps: 500,
            liqPenaltyBps: 500
        });
        IndexPerp perp = IndexPerp(
            payable(address(new ERC1967Proxy(address(new IndexPerp()), abi.encodeCall(IndexPerp.initialize, (p)))))
        );

        vault.setPerp(address(perp));
        insurance.setPerp(address(perp));

        vm.stopBroadcast();

        console2.log("UPGRADE_ADMIN", admin);
        console2.log("KEEPER", keeper);
        console2.log("PUSH_ORACLE", address(oracle));
        console2.log("INDEX_BASKET", address(basket));
        console2.log("PERP_VAULT", address(vault));
        console2.log("INSURANCE_FUND", address(insurance));
        console2.log("INDEX_PERP", address(perp));
    }
}

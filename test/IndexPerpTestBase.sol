// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PushOracle} from "../src/PushOracle.sol";
import {IndexBasket} from "../src/IndexBasket.sol";
import {PerpVault} from "../src/PerpVault.sol";
import {InsuranceFund} from "../src/InsuranceFund.sol";
import {IndexPerp} from "../src/IndexPerp.sol";
import {TestBase} from "./TestBase.sol";

contract IndexPerpTestBase is TestBase {
    PushOracle internal oracle;
    IndexBasket internal basket;
    PerpVault internal vault;
    InsuranceFund internal insurance;
    IndexPerp internal perp;

    address internal owner = address(0xA11AD);
    address internal keeper = address(0xCAFE);
    address internal lp = address(0x11D);
    address internal trader = address(0x7AD);
    bytes32 internal constant FEED = bytes32("ETHUSDC");

    function _proxy(address impl, bytes memory initData) internal returns (address) {
        return address(new ERC1967Proxy(impl, initData));
    }

    function _deployStack() internal {
        oracle = PushOracle(_proxy(address(new PushOracle()), abi.encodeCall(PushOracle.initialize, (owner, keeper))));

        IndexBasket.IndexLeg[] memory legs = new IndexBasket.IndexLeg[](1);
        legs[0] = IndexBasket.IndexLeg({kind: IndexBasket.LegKind.CALL, strike: 2000e18, weight: 1e18});
        basket = IndexBasket(
            _proxy(
                address(new IndexBasket()),
                abi.encodeCall(IndexBasket.initialize, (owner, address(oracle), FEED, 1 hours, 2100e18, 10000e18, legs))
            )
        );

        vault = PerpVault(payable(_proxy(address(new PerpVault()), abi.encodeCall(PerpVault.initialize, (owner, 9000)))));
        insurance = InsuranceFund(payable(_proxy(address(new InsuranceFund()), abi.encodeCall(InsuranceFund.initialize, (owner)))));

        IndexPerp.InitParams memory p = IndexPerp.InitParams({
            owner: owner,
            basket: address(basket),
            vault: address(vault),
            insurance: address(insurance),
            maxLeverage: 20e18,
            openFeeBps: 10,
            closeFeeBps: 10,
            borrowBase: 0,
            fundK: 0,
            mmBps: 500,
            liqPenaltyBps: 500
        });
        perp = IndexPerp(payable(_proxy(address(new IndexPerp()), abi.encodeCall(IndexPerp.initialize, (p)))));
    }

    function _wire() internal {
        vm.prank(owner);
        vault.setPerp(address(perp));
        vm.prank(owner);
        insurance.setPerp(address(perp));
    }

    function _push(uint256 price) internal {
        vm.prank(keeper);
        oracle.pushPrice(FEED, price);
    }

    function _setUpPerp(uint256 lpEth, uint256 insEth, uint256 price) internal {
        _deployStack();
        _wire();
        vm.deal(lp, lpEth);
        vm.deal(trader, 1_000 ether);
        vm.deal(address(this), insEth);
        insurance.deposit{value: insEth}();
        vm.prank(lp);
        vault.deposit{value: lpEth}();
        vm.warp(1_000_000);
        _push(price);
    }
}

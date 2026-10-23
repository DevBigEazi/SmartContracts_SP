// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {SellerPadiShipment} from "../src/SellerPadiShipment.sol";

interface IUUPSUpgradeable {
    function upgradeToAndCall(
        address newImplementation,
        bytes memory data
    ) external payable;
}

/**
 * @title UpgradeSellerPadiShipmentScript
 * @notice Deploys a new implementation of SellerPadiShipment and upgrades the UUPS Proxy on Avalanche C-Chain.
 */
contract UpgradeSellerPadiShipmentScript is Script {
    address public constant MAINNET_PROXY_ADDRESS =
        0xce4bF97e85212d9121e52c3F6fb2C8021Bf30012;

    function run() external {
        address proxyAddress = vm.envOr(
            "SHIPMENT_PROXY_ADDRESS",
            MAINNET_PROXY_ADDRESS
        );
        console2.log(
            "Upgrading SellerPadiShipment UUPS Proxy at:",
            proxyAddress
        );

        vm.startBroadcast();

        // 1. Deploy new implementation contract
        SellerPadiShipment newImplementation = new SellerPadiShipment();
        console2.log(
            "New SellerPadiShipment Implementation deployed at:",
            address(newImplementation)
        );

        // 2. Upgrade the Proxy contract to point to the new implementation
        IUUPSUpgradeable(proxyAddress).upgradeToAndCall(
            address(newImplementation),
            ""
        );
        console2.log("Successfully upgraded UUPS Proxy to new implementation!");

        vm.stopBroadcast();
    }
}

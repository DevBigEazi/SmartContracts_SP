// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {SellerPadiReceipt} from "../src/SellerPadiReceipt.sol";

interface IUUPSUpgradeable {
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable;
}

/**
 * @title UpgradeSellerPadiReceiptScript
 * @notice Deploys a new implementation of SellerPadiReceipt and upgrades the UUPS Proxy on Avalanche C-Chain.
 */
contract UpgradeSellerPadiReceiptScript is Script {
    address public constant PROXY_ADDRESS = 0x910Ba81487FE94E97A30EF72B139a3237b579ea5;
    // 0x910Ba81487FE94E97A30EF72B139a3237b579ea5
    function run() external {
        address proxyAddress = vm.envOr("RECEIPT_PROXY_ADDRESS", PROXY_ADDRESS);
        console2.log("Upgrading SellerPadiReceipt UUPS Proxy at:", proxyAddress);

        vm.startBroadcast();

        // 1. Deploy new implementation contract
        SellerPadiReceipt newImplementation = new SellerPadiReceipt();
        console2.log("New SellerPadiReceipt Implementation deployed at:", address(newImplementation));

        // 2. Upgrade the Proxy contract to point to the new implementation
        IUUPSUpgradeable(proxyAddress).upgradeToAndCall(address(newImplementation), "");
        console2.log("Successfully upgraded UUPS Proxy to new implementation!");

        vm.stopBroadcast();
    }
}

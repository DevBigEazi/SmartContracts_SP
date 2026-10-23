// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SellerPadiShipment} from "../src/SellerPadiShipment.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SellerPadiShipmentMockV2 is SellerPadiShipment {
    function version() external pure returns (string memory) {
        return "v2";
    }
}

contract SellerPadiShipmentTest is Test {
    SellerPadiShipment public sellerPadiShipment;
    address public proxyOwner;
    address public shipper;
    address public handler;
    address public recipient;
    uint256 public backendPrivateKey;
    address public backendSigner;

    bytes32 public constant TEST_PACKAGE_ID = keccak256("PKG-12345");
    string public constant TEST_SECRET = "SECRET-CODE-999";
    bytes32 public TEST_PACKAGE_HASH;

    function setUp() public {
        proxyOwner = address(this);
        shipper = address(0x1);
        handler = address(0x2);
        recipient = address(0x3);
        backendPrivateKey = 0xBEAF;
        backendSigner = vm.addr(backendPrivateKey);

        TEST_PACKAGE_HASH = keccak256(
            abi.encodePacked(TEST_PACKAGE_ID, TEST_SECRET)
        );

        // Deploy implementation
        SellerPadiShipment impl = new SellerPadiShipment();

        // Encode initializer
        bytes memory initData = abi.encodeWithSelector(
            SellerPadiShipment.initialize.selector,
            backendSigner
        );

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        // Wrap proxy in implementation interface
        sellerPadiShipment = SellerPadiShipment(address(proxy));
    }

    // --- Helper Functions to Generate Signatures ---

    function getRegisterSignature(
        address shipperAddr,
        bytes32 packageId,
        bytes32 packageHash,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                shipperAddr,
                packageId,
                packageHash,
                nonce,
                deadline,
                block.chainid,
                address(sellerPadiShipment)
            )
        );
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            backendPrivateKey,
            ethSignedMessageHash
        );
        return abi.encodePacked(r, s, v);
    }

    function getHandoverSignature(
        address operatorAddr,
        bytes32 packageId,
        address nextHandler,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                operatorAddr,
                packageId,
                nextHandler,
                nonce,
                deadline,
                block.chainid,
                address(sellerPadiShipment)
            )
        );
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            backendPrivateKey,
            ethSignedMessageHash
        );
        return abi.encodePacked(r, s, v);
    }

    function getVerifySignature(
        address callerAddr,
        bytes32 packageId,
        string memory innerSecret,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                callerAddr,
                packageId,
                keccak256(bytes(innerSecret)),
                nonce,
                deadline,
                block.chainid,
                address(sellerPadiShipment)
            )
        );
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            backendPrivateKey,
            ethSignedMessageHash
        );
        return abi.encodePacked(r, s, v);
    }

    function getDisputeSignature(
        address callerAddr,
        bytes32 packageId,
        string memory reason,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                callerAddr,
                packageId,
                keccak256(bytes(reason)),
                nonce,
                deadline,
                block.chainid,
                address(sellerPadiShipment)
            )
        );
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            backendPrivateKey,
            ethSignedMessageHash
        );
        return abi.encodePacked(r, s, v);
    }

    // --- Tests ---

    function test_Initialize() public view {
        assertEq(sellerPadiShipment.backendSigner(), backendSigner);
        assertEq(sellerPadiShipment.owner(), proxyOwner);
    }

    function test_RegisterShipment_Success() public {
        uint256 nonce = sellerPadiShipment.userNonces(shipper);
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = getRegisterSignature(
            shipper,
            TEST_PACKAGE_ID,
            TEST_PACKAGE_HASH,
            nonce,
            deadline
        );

        vm.prank(shipper);
        sellerPadiShipment.registerShipment(
            TEST_PACKAGE_ID,
            TEST_PACKAGE_HASH,
            deadline,
            signature
        );

        SellerPadiShipment.Shipment memory s = sellerPadiShipment.getShipment(
            TEST_PACKAGE_ID
        );
        assertEq(s.packageId, TEST_PACKAGE_ID);
        assertEq(s.packageHash, TEST_PACKAGE_HASH);
        assertEq(s.shipper, shipper);
        assertEq(uint8(s.status), uint8(SellerPadiShipment.Status.Created));
    }

    function test_RegisterShipment_RevertIfExpired() public {
        uint256 nonce = sellerPadiShipment.userNonces(shipper);
        uint256 deadline = block.timestamp - 1;
        bytes memory signature = getRegisterSignature(
            shipper,
            TEST_PACKAGE_ID,
            TEST_PACKAGE_HASH,
            nonce,
            deadline
        );

        vm.prank(shipper);
        vm.expectRevert(SellerPadiShipment.SignatureExpired.selector);
        sellerPadiShipment.registerShipment(
            TEST_PACKAGE_ID,
            TEST_PACKAGE_HASH,
            deadline,
            signature
        );
    }

    function test_LogHandover_Success() public {
        // Register first
        uint256 nonce = sellerPadiShipment.userNonces(shipper);
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = getRegisterSignature(
            shipper,
            TEST_PACKAGE_ID,
            TEST_PACKAGE_HASH,
            nonce,
            deadline
        );

        vm.prank(shipper);
        sellerPadiShipment.registerShipment(
            TEST_PACKAGE_ID,
            TEST_PACKAGE_HASH,
            deadline,
            signature
        );

        // Handover
        uint256 handlerNonce = sellerPadiShipment.userNonces(shipper);
        bytes memory handoverSig = getHandoverSignature(
            shipper,
            TEST_PACKAGE_ID,
            handler,
            handlerNonce,
            deadline
        );

        vm.prank(shipper);
        sellerPadiShipment.logHandover(
            TEST_PACKAGE_ID,
            handler,
            deadline,
            handoverSig
        );

        SellerPadiShipment.Shipment memory s = sellerPadiShipment.getShipment(
            TEST_PACKAGE_ID
        );
        assertEq(s.currentHandler, handler);
        assertEq(uint8(s.status), uint8(SellerPadiShipment.Status.InTransit));
    }

    function test_LogHandover_RevertIfAlreadyInTransit() public {
        // Register
        uint256 nonce = sellerPadiShipment.userNonces(shipper);
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = getRegisterSignature(
            shipper,
            TEST_PACKAGE_ID,
            TEST_PACKAGE_HASH,
            nonce,
            deadline
        );

        vm.prank(shipper);
        sellerPadiShipment.registerShipment(
            TEST_PACKAGE_ID,
            TEST_PACKAGE_HASH,
            deadline,
            signature
        );

        // First handover (Created -> InTransit)
        uint256 handoverNonce1 = sellerPadiShipment.userNonces(shipper);
        bytes memory handoverSig1 = getHandoverSignature(
            shipper,
            TEST_PACKAGE_ID,
            handler,
            handoverNonce1,
            deadline
        );
        vm.prank(shipper);
        sellerPadiShipment.logHandover(
            TEST_PACKAGE_ID,
            handler,
            deadline,
            handoverSig1
        );

        // Second handover attempt (InTransit -> InTransit) should revert
        address secondHandler = makeAddr("secondHandler");
        uint256 handoverNonce2 = sellerPadiShipment.userNonces(shipper);
        bytes memory handoverSig2 = getHandoverSignature(
            shipper,
            TEST_PACKAGE_ID,
            secondHandler,
            handoverNonce2,
            deadline
        );

        vm.prank(shipper);
        vm.expectRevert(
            abi.encodeWithSelector(
                SellerPadiShipment.InvalidStatusTransition.selector,
                TEST_PACKAGE_ID,
                SellerPadiShipment.Status.InTransit,
                SellerPadiShipment.Status.InTransit
            )
        );
        sellerPadiShipment.logHandover(
            TEST_PACKAGE_ID,
            secondHandler,
            deadline,
            handoverSig2
        );
    }

    function test_VerifyDelivery_Success() public {
        // Register
        uint256 nonce = sellerPadiShipment.userNonces(shipper);
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = getRegisterSignature(
            shipper,
            TEST_PACKAGE_ID,
            TEST_PACKAGE_HASH,
            nonce,
            deadline
        );

        vm.prank(shipper);
        sellerPadiShipment.registerShipment(
            TEST_PACKAGE_ID,
            TEST_PACKAGE_HASH,
            deadline,
            signature
        );

        // Handover to handler
        uint256 handoverNonce = sellerPadiShipment.userNonces(shipper);
        bytes memory handoverSig = getHandoverSignature(
            shipper,
            TEST_PACKAGE_ID,
            handler,
            handoverNonce,
            deadline
        );
        vm.prank(shipper);
        sellerPadiShipment.logHandover(
            TEST_PACKAGE_ID,
            handler,
            deadline,
            handoverSig
        );

        // Recipient verifies delivery
        uint256 recipientNonce = sellerPadiShipment.userNonces(recipient);
        bytes memory verifySig = getVerifySignature(
            recipient,
            TEST_PACKAGE_ID,
            TEST_SECRET,
            recipientNonce,
            deadline
        );

        vm.prank(recipient);
        sellerPadiShipment.verifyDelivery(
            TEST_PACKAGE_ID,
            TEST_SECRET,
            deadline,
            verifySig
        );

        SellerPadiShipment.Shipment memory s = sellerPadiShipment.getShipment(
            TEST_PACKAGE_ID
        );
        assertEq(uint8(s.status), uint8(SellerPadiShipment.Status.Verified));
    }

    function test_VerifyDelivery_RevertIfInvalidSecret() public {
        // Register
        uint256 nonce = sellerPadiShipment.userNonces(shipper);
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = getRegisterSignature(
            shipper,
            TEST_PACKAGE_ID,
            TEST_PACKAGE_HASH,
            nonce,
            deadline
        );

        vm.prank(shipper);
        sellerPadiShipment.registerShipment(
            TEST_PACKAGE_ID,
            TEST_PACKAGE_HASH,
            deadline,
            signature
        );

        // Handover to handler
        uint256 handoverNonce = sellerPadiShipment.userNonces(shipper);
        bytes memory handoverSig = getHandoverSignature(
            shipper,
            TEST_PACKAGE_ID,
            handler,
            handoverNonce,
            deadline
        );
        vm.prank(shipper);
        sellerPadiShipment.logHandover(
            TEST_PACKAGE_ID,
            handler,
            deadline,
            handoverSig
        );

        // Recipient tries to verify with incorrect secret
        uint256 recipientNonce = sellerPadiShipment.userNonces(recipient);
        bytes memory verifySig = getVerifySignature(
            recipient,
            TEST_PACKAGE_ID,
            "WRONG-SECRET",
            recipientNonce,
            deadline
        );

        vm.prank(recipient);
        vm.expectRevert(SellerPadiShipment.InvalidSecret.selector);
        sellerPadiShipment.verifyDelivery(
            TEST_PACKAGE_ID,
            "WRONG-SECRET",
            deadline,
            verifySig
        );
    }

    function test_DisputeDelivery_Success() public {
        // Register
        uint256 nonce = sellerPadiShipment.userNonces(shipper);
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = getRegisterSignature(
            shipper,
            TEST_PACKAGE_ID,
            TEST_PACKAGE_HASH,
            nonce,
            deadline
        );

        vm.prank(shipper);
        sellerPadiShipment.registerShipment(
            TEST_PACKAGE_ID,
            TEST_PACKAGE_HASH,
            deadline,
            signature
        );

        // Handover to handler (InTransit)
        uint256 handoverNonce = sellerPadiShipment.userNonces(shipper);
        bytes memory handoverSig = getHandoverSignature(
            shipper,
            TEST_PACKAGE_ID,
            handler,
            handoverNonce,
            deadline
        );
        vm.prank(shipper);
        sellerPadiShipment.logHandover(
            TEST_PACKAGE_ID,
            handler,
            deadline,
            handoverSig
        );

        // Dispute
        string memory reason = "Tamper sticker broken!";
        uint256 disputeNonce = sellerPadiShipment.userNonces(recipient);
        bytes memory disputeSig = getDisputeSignature(
            recipient,
            TEST_PACKAGE_ID,
            reason,
            disputeNonce,
            deadline
        );

        vm.prank(recipient);
        sellerPadiShipment.disputeDelivery(
            TEST_PACKAGE_ID,
            reason,
            deadline,   
            disputeSig
        );

        SellerPadiShipment.Shipment memory s = sellerPadiShipment.getShipment(
            TEST_PACKAGE_ID
        );
        assertEq(uint8(s.status), uint8(SellerPadiShipment.Status.Disputed));
    }

    function test_DisputeDelivery_RevertIfNotInTransit() public {
        // Register (status is Created)
        uint256 nonce = sellerPadiShipment.userNonces(shipper);
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = getRegisterSignature(
            shipper,
            TEST_PACKAGE_ID,
            TEST_PACKAGE_HASH,
            nonce,
            deadline
        );

        vm.prank(shipper);
        sellerPadiShipment.registerShipment(
            TEST_PACKAGE_ID,
            TEST_PACKAGE_HASH,
            deadline,
            signature
        );

        // Dispute directly from Created status -> should revert
        string memory reason = "Tamper sticker broken!";
        uint256 disputeNonce = sellerPadiShipment.userNonces(recipient);
        bytes memory disputeSig = getDisputeSignature(
            recipient,
            TEST_PACKAGE_ID,
            reason,
            disputeNonce,
            deadline
        );

        vm.prank(recipient);
        vm.expectRevert(
            abi.encodeWithSelector(
                SellerPadiShipment.InvalidStatusTransition.selector,
                TEST_PACKAGE_ID,
                SellerPadiShipment.Status.Created,
                SellerPadiShipment.Status.Disputed
            )
        );
        sellerPadiShipment.disputeDelivery(
            TEST_PACKAGE_ID,
            reason,
            deadline,
            disputeSig
        );
    }
}

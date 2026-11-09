// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SellerPadiShipment} from "../src/SellerPadiShipment.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

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

        TEST_PACKAGE_HASH = keccak256(abi.encodePacked(TEST_PACKAGE_ID, TEST_SECRET));

        // Deploy implementation
        SellerPadiShipment impl = new SellerPadiShipment();

        // Encode initializer
        bytes memory initData = abi.encodeWithSelector(SellerPadiShipment.initialize.selector, backendSigner);

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
                shipperAddr, packageId, packageHash, nonce, deadline, block.chainid, address(sellerPadiShipment)
            )
        );
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(backendPrivateKey, ethSignedMessageHash);
        return abi.encodePacked(r, s, v);
    }

    function getBatchSignature(
        address relayerAddr,
        bytes32 merkleRoot,
        uint256 recordCount,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                relayerAddr, merkleRoot, recordCount, nonce, deadline, block.chainid, address(sellerPadiShipment)
            )
        );
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(backendPrivateKey, ethSignedMessageHash);
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
                operatorAddr, packageId, nextHandler, nonce, deadline, block.chainid, address(sellerPadiShipment)
            )
        );
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(backendPrivateKey, ethSignedMessageHash);
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
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(backendPrivateKey, ethSignedMessageHash);
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
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(backendPrivateKey, ethSignedMessageHash);
        return abi.encodePacked(r, s, v);
    }

    function getReturnHandoverSignature(
        address callerAddr,
        bytes32 packageId,
        address rider,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(
            abi.encodePacked(callerAddr, packageId, rider, nonce, deadline, block.chainid, address(sellerPadiShipment))
        );
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(backendPrivateKey, ethSignedMessageHash);
        return abi.encodePacked(r, s, v);
    }

    function getStoreReturnSignature(address callerAddr, bytes32 packageId, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes memory)
    {
        bytes32 messageHash = keccak256(
            abi.encodePacked(callerAddr, packageId, nonce, deadline, block.chainid, address(sellerPadiShipment))
        );
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(backendPrivateKey, ethSignedMessageHash);
        return abi.encodePacked(r, s, v);
    }

    function getResolveSignature(
        address callerAddr,
        bytes32 packageId,
        string memory resolutionType,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                callerAddr,
                packageId,
                keccak256(bytes(resolutionType)),
                nonce,
                deadline,
                block.chainid,
                address(sellerPadiShipment)
            )
        );
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(backendPrivateKey, ethSignedMessageHash);
        return abi.encodePacked(r, s, v);
    }

    function getRedispatchSignature(
        address callerAddr,
        bytes32 packageId,
        bytes32 newPackageHash,
        address nextHandler,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                callerAddr,
                packageId,
                newPackageHash,
                nextHandler,
                nonce,
                deadline,
                block.chainid,
                address(sellerPadiShipment)
            )
        );
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(backendPrivateKey, ethSignedMessageHash);
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
        bytes memory signature = getRegisterSignature(shipper, TEST_PACKAGE_ID, TEST_PACKAGE_HASH, nonce, deadline);

        vm.prank(shipper);
        sellerPadiShipment.registerShipment(TEST_PACKAGE_ID, TEST_PACKAGE_HASH, deadline, signature);

        SellerPadiShipment.Shipment memory s = sellerPadiShipment.getShipment(TEST_PACKAGE_ID);
        assertEq(s.packageId, TEST_PACKAGE_ID);
        assertEq(s.packageHash, TEST_PACKAGE_HASH);
        assertEq(s.shipper, shipper);
        assertEq(uint8(s.status), uint8(SellerPadiShipment.Status.Created));
    }

    function test_RegisterShipment_RevertIfExpired() public {
        uint256 nonce = sellerPadiShipment.userNonces(shipper);
        uint256 deadline = block.timestamp - 1;
        bytes memory signature = getRegisterSignature(shipper, TEST_PACKAGE_ID, TEST_PACKAGE_HASH, nonce, deadline);

        vm.prank(shipper);
        vm.expectRevert(SellerPadiShipment.SignatureExpired.selector);
        sellerPadiShipment.registerShipment(TEST_PACKAGE_ID, TEST_PACKAGE_HASH, deadline, signature);
    }

    function test_LogHandover_Success() public {
        // Register first
        uint256 nonce = sellerPadiShipment.userNonces(shipper);
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = getRegisterSignature(shipper, TEST_PACKAGE_ID, TEST_PACKAGE_HASH, nonce, deadline);

        vm.prank(shipper);
        sellerPadiShipment.registerShipment(TEST_PACKAGE_ID, TEST_PACKAGE_HASH, deadline, signature);

        // Handover
        uint256 handlerNonce = sellerPadiShipment.userNonces(shipper);
        bytes memory handoverSig = getHandoverSignature(shipper, TEST_PACKAGE_ID, handler, handlerNonce, deadline);

        vm.prank(shipper);
        sellerPadiShipment.logHandover(TEST_PACKAGE_ID, handler, deadline, handoverSig);

        SellerPadiShipment.Shipment memory s = sellerPadiShipment.getShipment(TEST_PACKAGE_ID);
        assertEq(s.currentHandler, handler);
        assertEq(uint8(s.status), uint8(SellerPadiShipment.Status.InTransit));
    }

    function test_LogHandover_RevertIfAlreadyInTransit() public {
        // Register
        uint256 nonce = sellerPadiShipment.userNonces(shipper);
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = getRegisterSignature(shipper, TEST_PACKAGE_ID, TEST_PACKAGE_HASH, nonce, deadline);

        vm.prank(shipper);
        sellerPadiShipment.registerShipment(TEST_PACKAGE_ID, TEST_PACKAGE_HASH, deadline, signature);

        // First handover (Created -> InTransit)
        uint256 handoverNonce1 = sellerPadiShipment.userNonces(shipper);
        bytes memory handoverSig1 = getHandoverSignature(shipper, TEST_PACKAGE_ID, handler, handoverNonce1, deadline);
        vm.prank(shipper);
        sellerPadiShipment.logHandover(TEST_PACKAGE_ID, handler, deadline, handoverSig1);

        // Second handover attempt (InTransit -> InTransit) should revert
        address secondHandler = makeAddr("secondHandler");
        uint256 handoverNonce2 = sellerPadiShipment.userNonces(shipper);
        bytes memory handoverSig2 =
            getHandoverSignature(shipper, TEST_PACKAGE_ID, secondHandler, handoverNonce2, deadline);

        vm.prank(shipper);
        vm.expectRevert(
            abi.encodeWithSelector(
                SellerPadiShipment.InvalidStatusTransition.selector,
                TEST_PACKAGE_ID,
                SellerPadiShipment.Status.InTransit,
                SellerPadiShipment.Status.InTransit
            )
        );
        sellerPadiShipment.logHandover(TEST_PACKAGE_ID, secondHandler, deadline, handoverSig2);
    }

    function test_VerifyDelivery_Success() public {
        // Register
        uint256 nonce = sellerPadiShipment.userNonces(shipper);
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = getRegisterSignature(shipper, TEST_PACKAGE_ID, TEST_PACKAGE_HASH, nonce, deadline);

        vm.prank(shipper);
        sellerPadiShipment.registerShipment(TEST_PACKAGE_ID, TEST_PACKAGE_HASH, deadline, signature);

        // Handover to handler
        uint256 handoverNonce = sellerPadiShipment.userNonces(shipper);
        bytes memory handoverSig = getHandoverSignature(shipper, TEST_PACKAGE_ID, handler, handoverNonce, deadline);
        vm.prank(shipper);
        sellerPadiShipment.logHandover(TEST_PACKAGE_ID, handler, deadline, handoverSig);

        // Recipient verifies delivery
        uint256 recipientNonce = sellerPadiShipment.userNonces(recipient);
        bytes memory verifySig = getVerifySignature(recipient, TEST_PACKAGE_ID, TEST_SECRET, recipientNonce, deadline);

        vm.prank(recipient);
        sellerPadiShipment.verifyDelivery(TEST_PACKAGE_ID, TEST_SECRET, deadline, verifySig);

        SellerPadiShipment.Shipment memory s = sellerPadiShipment.getShipment(TEST_PACKAGE_ID);
        assertEq(uint8(s.status), uint8(SellerPadiShipment.Status.Verified));
    }

    function test_VerifyDelivery_RevertIfInvalidSecret() public {
        // Register
        uint256 nonce = sellerPadiShipment.userNonces(shipper);
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = getRegisterSignature(shipper, TEST_PACKAGE_ID, TEST_PACKAGE_HASH, nonce, deadline);

        vm.prank(shipper);
        sellerPadiShipment.registerShipment(TEST_PACKAGE_ID, TEST_PACKAGE_HASH, deadline, signature);

        // Handover to handler
        uint256 handoverNonce = sellerPadiShipment.userNonces(shipper);
        bytes memory handoverSig = getHandoverSignature(shipper, TEST_PACKAGE_ID, handler, handoverNonce, deadline);
        vm.prank(shipper);
        sellerPadiShipment.logHandover(TEST_PACKAGE_ID, handler, deadline, handoverSig);

        // Recipient tries to verify with incorrect secret
        uint256 recipientNonce = sellerPadiShipment.userNonces(recipient);
        bytes memory verifySig =
            getVerifySignature(recipient, TEST_PACKAGE_ID, "WRONG-SECRET", recipientNonce, deadline);

        vm.prank(recipient);
        vm.expectRevert(SellerPadiShipment.InvalidSecret.selector);
        sellerPadiShipment.verifyDelivery(TEST_PACKAGE_ID, "WRONG-SECRET", deadline, verifySig);
    }

    function test_DisputeDelivery_Success() public {
        // Register
        uint256 nonce = sellerPadiShipment.userNonces(shipper);
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = getRegisterSignature(shipper, TEST_PACKAGE_ID, TEST_PACKAGE_HASH, nonce, deadline);

        vm.prank(shipper);
        sellerPadiShipment.registerShipment(TEST_PACKAGE_ID, TEST_PACKAGE_HASH, deadline, signature);

        // Handover to handler (InTransit)
        uint256 handoverNonce = sellerPadiShipment.userNonces(shipper);
        bytes memory handoverSig = getHandoverSignature(shipper, TEST_PACKAGE_ID, handler, handoverNonce, deadline);
        vm.prank(shipper);
        sellerPadiShipment.logHandover(TEST_PACKAGE_ID, handler, deadline, handoverSig);

        // Dispute
        string memory reason = "Tamper sticker broken!";
        uint256 disputeNonce = sellerPadiShipment.userNonces(recipient);
        bytes memory disputeSig = getDisputeSignature(recipient, TEST_PACKAGE_ID, reason, disputeNonce, deadline);

        vm.prank(recipient);
        sellerPadiShipment.disputeDelivery(TEST_PACKAGE_ID, reason, deadline, disputeSig);

        SellerPadiShipment.Shipment memory s = sellerPadiShipment.getShipment(TEST_PACKAGE_ID);
        assertEq(uint8(s.status), uint8(SellerPadiShipment.Status.Disputed));
    }

    function test_DisputeDelivery_RevertIfNotInTransit() public {
        // Register (status is Created)
        uint256 nonce = sellerPadiShipment.userNonces(shipper);
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = getRegisterSignature(shipper, TEST_PACKAGE_ID, TEST_PACKAGE_HASH, nonce, deadline);

        vm.prank(shipper);
        sellerPadiShipment.registerShipment(TEST_PACKAGE_ID, TEST_PACKAGE_HASH, deadline, signature);

        // Dispute directly from Created status -> should revert
        string memory reason = "Tamper sticker broken!";
        uint256 disputeNonce = sellerPadiShipment.userNonces(recipient);
        bytes memory disputeSig = getDisputeSignature(recipient, TEST_PACKAGE_ID, reason, disputeNonce, deadline);

        vm.prank(recipient);
        vm.expectRevert(
            abi.encodeWithSelector(
                SellerPadiShipment.InvalidStatusTransition.selector,
                TEST_PACKAGE_ID,
                SellerPadiShipment.Status.Created,
                SellerPadiShipment.Status.Disputed
            )
        );
        sellerPadiShipment.disputeDelivery(TEST_PACKAGE_ID, reason, deadline, disputeSig);
    }

    function _setupDisputedShipment(uint256 deadline) internal {
        uint256 nonce = sellerPadiShipment.userNonces(shipper);
        bytes memory sig = getRegisterSignature(shipper, TEST_PACKAGE_ID, TEST_PACKAGE_HASH, nonce, deadline);
        vm.prank(shipper);
        sellerPadiShipment.registerShipment(TEST_PACKAGE_ID, TEST_PACKAGE_HASH, deadline, sig);

        nonce = sellerPadiShipment.userNonces(shipper);
        sig = getHandoverSignature(shipper, TEST_PACKAGE_ID, handler, nonce, deadline);
        vm.prank(shipper);
        sellerPadiShipment.logHandover(TEST_PACKAGE_ID, handler, deadline, sig);

        string memory reason = "Wrong item received";
        nonce = sellerPadiShipment.userNonces(recipient);
        sig = getDisputeSignature(recipient, TEST_PACKAGE_ID, reason, nonce, deadline);
        vm.prank(recipient);
        sellerPadiShipment.disputeDelivery(TEST_PACKAGE_ID, reason, deadline, sig);
    }

    function test_ReverseLogistics_PathA_Resolved() public {
        uint256 deadline = block.timestamp + 1 hours;
        _setupDisputedShipment(deadline);

        assertEq(
            uint8(sellerPadiShipment.getShipment(TEST_PACKAGE_ID).status), uint8(SellerPadiShipment.Status.Disputed)
        );

        // 4. Return handover back to rider
        address returnRider = address(0x4);
        uint256 nonce = sellerPadiShipment.userNonces(recipient);
        bytes memory sig = getReturnHandoverSignature(recipient, TEST_PACKAGE_ID, returnRider, nonce, deadline);
        vm.prank(recipient);
        sellerPadiShipment.handoverReturn(TEST_PACKAGE_ID, returnRider, deadline, sig);

        SellerPadiShipment.Shipment memory sRet = sellerPadiShipment.getShipment(TEST_PACKAGE_ID);
        assertEq(uint8(sRet.status), uint8(SellerPadiShipment.Status.ReturnTransit));
        assertEq(sRet.currentHandler, returnRider);

        // 5. Store confirms receipt of returned goods
        nonce = sellerPadiShipment.userNonces(shipper);
        sig = getStoreReturnSignature(shipper, TEST_PACKAGE_ID, nonce, deadline);
        vm.prank(shipper);
        sellerPadiShipment.confirmStoreReturn(TEST_PACKAGE_ID, deadline, sig);

        SellerPadiShipment.Shipment memory sStore = sellerPadiShipment.getShipment(TEST_PACKAGE_ID);
        assertEq(uint8(sStore.status), uint8(SellerPadiShipment.Status.ReturnedToStore));
        assertEq(sStore.currentHandler, shipper);

        // 6. Path A: Resolve dispute (Refunded)
        string memory resolution = "Refunded & Stock Restored";
        nonce = sellerPadiShipment.userNonces(shipper);
        sig = getResolveSignature(shipper, TEST_PACKAGE_ID, resolution, nonce, deadline);
        vm.prank(shipper);
        sellerPadiShipment.resolveDispute(TEST_PACKAGE_ID, resolution, deadline, sig);

        assertEq(
            uint8(sellerPadiShipment.getShipment(TEST_PACKAGE_ID).status), uint8(SellerPadiShipment.Status.Resolved)
        );
    }

    function test_ReverseLogistics_PathB_Redispatch_And_Verify() public {
        uint256 deadline = block.timestamp + 1 hours;
        _setupDisputedShipment(deadline);

        // Handover return
        uint256 nonce = sellerPadiShipment.userNonces(recipient);
        bytes memory sig = getReturnHandoverSignature(recipient, TEST_PACKAGE_ID, handler, nonce, deadline);
        vm.prank(recipient);
        sellerPadiShipment.handoverReturn(TEST_PACKAGE_ID, handler, deadline, sig);

        // Store return
        nonce = sellerPadiShipment.userNonces(shipper);
        sig = getStoreReturnSignature(shipper, TEST_PACKAGE_ID, nonce, deadline);
        vm.prank(shipper);
        sellerPadiShipment.confirmStoreReturn(TEST_PACKAGE_ID, deadline, sig);

        // Re-dispatch with fresh scratch-off secret PIN
        string memory NEW_SECRET = "SP-NEW-SECRET-456";
        bytes32 NEW_PACKAGE_HASH = keccak256(abi.encodePacked(TEST_PACKAGE_ID, NEW_SECRET));
        address newRider = address(0x5);

        nonce = sellerPadiShipment.userNonces(shipper);
        sig = getRedispatchSignature(shipper, TEST_PACKAGE_ID, NEW_PACKAGE_HASH, newRider, nonce, deadline);
        vm.prank(shipper);
        sellerPadiShipment.redispatchShipment(TEST_PACKAGE_ID, NEW_PACKAGE_HASH, newRider, deadline, sig);

        SellerPadiShipment.Shipment memory sRedispatched = sellerPadiShipment.getShipment(TEST_PACKAGE_ID);
        assertEq(uint8(sRedispatched.status), uint8(SellerPadiShipment.Status.InTransit));
        assertEq(sRedispatched.currentHandler, newRider);
        assertEq(sRedispatched.packageHash, NEW_PACKAGE_HASH);

        // Old secret must revert
        nonce = sellerPadiShipment.userNonces(recipient);
        sig = getVerifySignature(recipient, TEST_PACKAGE_ID, TEST_SECRET, nonce, deadline);
        vm.prank(recipient);
        vm.expectRevert(SellerPadiShipment.InvalidSecret.selector);
        sellerPadiShipment.verifyDelivery(TEST_PACKAGE_ID, TEST_SECRET, deadline, sig);

        // New secret successfully verifies redelivery
        nonce = sellerPadiShipment.userNonces(recipient);
        sig = getVerifySignature(recipient, TEST_PACKAGE_ID, NEW_SECRET, nonce, deadline);
        vm.prank(recipient);
        sellerPadiShipment.verifyDelivery(TEST_PACKAGE_ID, NEW_SECRET, deadline, sig);

        assertEq(
            uint8(sellerPadiShipment.getShipment(TEST_PACKAGE_ID).status), uint8(SellerPadiShipment.Status.Verified)
        );
    }

    function test_ReverseLogistics_HandoverReturn_RevertIfNotDisputed() public {
        uint256 deadline = block.timestamp + 1 hours;

        // Register and Handover to handler (status is InTransit, not Disputed)
        uint256 regNonce = sellerPadiShipment.userNonces(shipper);
        bytes memory regSig = getRegisterSignature(shipper, TEST_PACKAGE_ID, TEST_PACKAGE_HASH, regNonce, deadline);
        vm.prank(shipper);
        sellerPadiShipment.registerShipment(TEST_PACKAGE_ID, TEST_PACKAGE_HASH, deadline, regSig);

        uint256 retHandNonce = sellerPadiShipment.userNonces(recipient);
        bytes memory retHandSig =
            getReturnHandoverSignature(recipient, TEST_PACKAGE_ID, handler, retHandNonce, deadline);

        vm.prank(recipient);
        vm.expectRevert(
            abi.encodeWithSelector(
                SellerPadiShipment.InvalidStatusTransition.selector,
                TEST_PACKAGE_ID,
                SellerPadiShipment.Status.Created,
                SellerPadiShipment.Status.ReturnTransit
            )
        );
        sellerPadiShipment.handoverReturn(TEST_PACKAGE_ID, handler, deadline, retHandSig);
    }

    function test_ReverseLogistics_ConfirmStoreReturn_RevertIfNotReturnTransit() public {
        uint256 deadline = block.timestamp + 1 hours;

        uint256 storeNonce = sellerPadiShipment.userNonces(shipper);
        bytes memory storeSig = getStoreReturnSignature(shipper, TEST_PACKAGE_ID, storeNonce, deadline);

        // Not even registered -> revert ShipmentNotFound
        vm.prank(shipper);
        vm.expectRevert(abi.encodeWithSelector(SellerPadiShipment.ShipmentNotFound.selector, TEST_PACKAGE_ID));
        sellerPadiShipment.confirmStoreReturn(TEST_PACKAGE_ID, deadline, storeSig);
    }

    function test_ReverseLogistics_ExpiredSignature_Reverts() public {
        uint256 deadline = block.timestamp - 1; // Expired

        bytes memory emptySig = hex"";
        vm.expectRevert(SellerPadiShipment.SignatureExpired.selector);
        sellerPadiShipment.handoverReturn(TEST_PACKAGE_ID, handler, deadline, emptySig);
    }

    // --- Merkle Batch Tests ---

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function test_RegisterBatch_Success() public {
        bytes32 leaf0 = keccak256("PACKAGE-001");
        bytes32 leaf1 = keccak256("PACKAGE-002");
        bytes32 merkleRoot = _hashPair(leaf0, leaf1);
        uint32 recordCount = 2;
        uint256 deadline = block.timestamp + 1 hours;

        address relayer = address(0xBB);
        bytes memory sig = getBatchSignature(relayer, merkleRoot, recordCount, 0, deadline);

        vm.prank(relayer);
        vm.expectEmit(true, true, false, true);
        emit SellerPadiShipment.ShipmentBatchRegistered(merkleRoot, relayer, recordCount, block.timestamp);
        sellerPadiShipment.registerShipmentBatch(merkleRoot, recordCount, deadline, sig);

        // Verify batch storage
        SellerPadiShipment.BatchRecord memory batch = sellerPadiShipment.getBatch(merkleRoot);
        assertEq(batch.merkleRoot, merkleRoot);
        assertEq(batch.relayer, relayer);
        assertEq(batch.recordCount, recordCount);
        assertEq(batch.anchoredAt, uint40(block.timestamp));

        // Verify Merkle inclusion proofs
        bytes32[] memory proof0 = new bytes32[](1);
        proof0[0] = leaf1;
        assertTrue(sellerPadiShipment.verifyShipmentProof(leaf0, proof0, merkleRoot));

        bytes32[] memory proof1 = new bytes32[](1);
        proof1[0] = leaf0;
        assertTrue(sellerPadiShipment.verifyShipmentProof(leaf1, proof1, merkleRoot));

        // Tampered leaf fails
        bytes32 fakeLeaf = keccak256("PACKAGE-FAKE");
        assertFalse(sellerPadiShipment.verifyShipmentProof(fakeLeaf, proof0, merkleRoot));

        // Non-existent batch fails
        bytes32 nonExistentRoot = keccak256("UNKNOWN-ROOT");
        assertFalse(sellerPadiShipment.verifyShipmentProof(leaf0, proof0, nonExistentRoot));
    }

    function test_RegisterBatch_ZeroRootReverts() public {
        address relayer = address(0xBB);
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = getBatchSignature(relayer, bytes32(0), 10, 0, deadline);

        vm.prank(relayer);
        vm.expectRevert(SellerPadiShipment.InvalidMerkleRoot.selector);
        sellerPadiShipment.registerShipmentBatch(bytes32(0), 10, deadline, sig);
    }

    function test_RegisterBatch_ZeroCountReverts() public {
        address relayer = address(0xBB);
        bytes32 root = keccak256("SOME_ROOT");
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = getBatchSignature(relayer, root, 0, 0, deadline);

        vm.prank(relayer);
        vm.expectRevert(SellerPadiShipment.InvalidRecordCount.selector);
        sellerPadiShipment.registerShipmentBatch(root, 0, deadline, sig);
    }

    function test_RegisterBatch_ReplayReverts() public {
        bytes32 root = keccak256("REPLAY_ROOT");
        uint32 count = 5;
        uint256 deadline = block.timestamp + 1 hours;
        address relayer = address(0xBB);
        bytes memory sig = getBatchSignature(relayer, root, count, 0, deadline);

        vm.prank(relayer);
        sellerPadiShipment.registerShipmentBatch(root, count, deadline, sig);

        // Try registering again with the same signature -> Reverts with BatchAlreadyExists
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(SellerPadiShipment.BatchAlreadyExists.selector, root));
        sellerPadiShipment.registerShipmentBatch(root, count, deadline, sig);
    }

    function test_RegisterBatch_RevertIfExpired() public {
        bytes32 root = keccak256("EXPIRED_ROOT");
        uint32 count = 3;
        uint256 deadline = block.timestamp - 1;
        address relayer = address(0xBB);
        bytes memory sig = getBatchSignature(relayer, root, count, 0, deadline);

        vm.prank(relayer);
        vm.expectRevert(SellerPadiShipment.SignatureExpired.selector);
        sellerPadiShipment.registerShipmentBatch(root, count, deadline, sig);
    }

    function test_RegisterBatch_InvalidSignature() public {
        bytes32 root = keccak256("INVALID_SIG_ROOT");
        uint32 count = 3;
        uint256 deadline = block.timestamp + 1 hours;
        address relayer = address(0xBB);

        // Sign with unauthorized key
        uint256 badKey = 0x123456789;
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                relayer, root, uint256(count), uint256(0), deadline, block.chainid, address(sellerPadiShipment)
            )
        );
        bytes32 ethSigned = MessageHashUtils.toEthSignedMessageHash(msgHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(badKey, ethSigned);
        bytes memory badSig = abi.encodePacked(r, s, v);

        vm.prank(relayer);
        vm.expectRevert(SellerPadiShipment.InvalidSignature.selector);
        sellerPadiShipment.registerShipmentBatch(root, count, deadline, badSig);
    }
}

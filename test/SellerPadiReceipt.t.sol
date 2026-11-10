// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SellerPadiReceipt} from "../src/SellerPadiReceipt.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract SellerPadiReceiptMockV2 is SellerPadiReceipt {
    function version() external pure returns (string memory) {
        return "v2";
    }
}

contract SellerPadiReceiptTest is Test {
    SellerPadiReceipt public sellerPadiReceipt;
    address public proxyOwner;
    address public merchant;
    address public otherUser;
    uint256 public backendPrivateKey;
    address public backendSigner;

    bytes32 public constant TEST_RECEIPT_HASH = keccak256("SP-REC-2026-0001");
    bytes32 public constant TEST_RECEIPT_HASH_2 = keccak256("SP-REC-2026-0002");

    function setUp() public {
        proxyOwner = address(this);
        merchant = address(0x11);
        otherUser = address(0x22);
        backendPrivateKey = 0xBEAF;
        backendSigner = vm.addr(backendPrivateKey);

        // Deploy implementation
        SellerPadiReceipt impl = new SellerPadiReceipt();

        // Encode initializer
        bytes memory initData = abi.encodeWithSelector(SellerPadiReceipt.initialize.selector, backendSigner);

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        // Wrap proxy in implementation interface
        sellerPadiReceipt = SellerPadiReceipt(address(proxy));
    }

    // --- Signature Generation Helpers ---

    function getRegisterSignature(
        address merchantAddr,
        bytes32 receiptHash,
        bytes32 parentReceiptHash,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                merchantAddr, receiptHash, parentReceiptHash, nonce, deadline, block.chainid, address(sellerPadiReceipt)
            )
        );
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
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
                relayerAddr, merkleRoot, recordCount, nonce, deadline, block.chainid, address(sellerPadiReceipt)
            )
        );
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(backendPrivateKey, ethSignedMessageHash);
        return abi.encodePacked(r, s, v);
    }

    function getVoidSignature(
        address callerAddr,
        bytes32 receiptHash,
        string memory reason,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                callerAddr,
                receiptHash,
                keccak256(bytes(reason)),
                nonce,
                deadline,
                block.chainid,
                address(sellerPadiReceipt)
            )
        );
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(backendPrivateKey, ethSignedMessageHash);
        return abi.encodePacked(r, s, v);
    }

    // --- Tests ---

    function test_Initialize() public view {
        assertEq(sellerPadiReceipt.owner(), proxyOwner);
        assertEq(sellerPadiReceipt.backendSigner(), backendSigner);
    }

    function test_CannotInitializeTwice() public {
        vm.expectRevert();
        sellerPadiReceipt.initialize(backendSigner);
    }

    function test_RegisterReceipt_Success() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = getRegisterSignature(merchant, TEST_RECEIPT_HASH, bytes32(0), 0, deadline);

        vm.prank(merchant);
        sellerPadiReceipt.registerReceipt(TEST_RECEIPT_HASH, bytes32(0), deadline, sig);

        SellerPadiReceipt.ReceiptRecord memory record = sellerPadiReceipt.getReceipt(TEST_RECEIPT_HASH);
        assertEq(record.receiptHash, TEST_RECEIPT_HASH);
        assertEq(record.parentReceiptHash, bytes32(0));
        assertEq(record.merchant, merchant);
        assertEq(uint8(record.status), uint8(SellerPadiReceipt.Status.Issued));
        assertEq(record.issuedAt, uint40(block.timestamp));
        assertEq(record.voidedAt, 0);
        assertEq(sellerPadiReceipt.userNonces(merchant), 1);
    }

    function test_RegisterReceipt_RevertIfExpired() public {
        uint256 deadline = block.timestamp - 1;
        bytes memory sig = getRegisterSignature(merchant, TEST_RECEIPT_HASH, bytes32(0), 0, deadline);

        vm.prank(merchant);
        vm.expectRevert(SellerPadiReceipt.SignatureExpired.selector);
        sellerPadiReceipt.registerReceipt(TEST_RECEIPT_HASH, bytes32(0), deadline, sig);
    }

    function test_RegisterReceipt_ZeroHashReverts() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = getRegisterSignature(merchant, bytes32(0), bytes32(0), 0, deadline);

        vm.prank(merchant);
        vm.expectRevert(SellerPadiReceipt.InvalidReceiptHash.selector);
        sellerPadiReceipt.registerReceipt(bytes32(0), bytes32(0), deadline, sig);
    }

    function test_RegisterReceipt_InvalidSignature() public {
        uint256 deadline = block.timestamp + 1 hours;
        // Sign with a different key
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                merchant, TEST_RECEIPT_HASH, bytes32(0), uint256(0), deadline, block.chainid, address(sellerPadiReceipt)
            )
        );
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x9999, ethSignedMessageHash);
        bytes memory invalidSig = abi.encodePacked(r, s, v);

        vm.prank(merchant);
        vm.expectRevert(SellerPadiReceipt.InvalidSignature.selector);
        sellerPadiReceipt.registerReceipt(TEST_RECEIPT_HASH, bytes32(0), deadline, invalidSig);
    }

    function test_RegisterReceipt_ReplayReverts() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = getRegisterSignature(merchant, TEST_RECEIPT_HASH, bytes32(0), 0, deadline);

        vm.prank(merchant);
        sellerPadiReceipt.registerReceipt(TEST_RECEIPT_HASH, bytes32(0), deadline, sig);

        // Attempt to replay with same signature
        vm.prank(merchant);
        vm.expectRevert(SellerPadiReceipt.InvalidSignature.selector);
        sellerPadiReceipt.registerReceipt(TEST_RECEIPT_HASH_2, bytes32(0), deadline, sig);
    }

    function test_RegisterReceipt_AlreadyExists() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = getRegisterSignature(merchant, TEST_RECEIPT_HASH, bytes32(0), 0, deadline);

        vm.prank(merchant);
        sellerPadiReceipt.registerReceipt(TEST_RECEIPT_HASH, bytes32(0), deadline, sig);

        // Try registering exact same hash with new nonce
        bytes memory sig2 = getRegisterSignature(merchant, TEST_RECEIPT_HASH, bytes32(0), 1, deadline);
        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(SellerPadiReceipt.ReceiptAlreadyExists.selector, TEST_RECEIPT_HASH));
        sellerPadiReceipt.registerReceipt(TEST_RECEIPT_HASH, bytes32(0), deadline, sig2);
    }

    function test_RegisterReceipt_WithParentVoidedReceipt() public {
        // First register and void parent receipt
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory regSig = getRegisterSignature(merchant, TEST_RECEIPT_HASH, bytes32(0), 0, deadline);

        vm.prank(merchant);
        sellerPadiReceipt.registerReceipt(TEST_RECEIPT_HASH, bytes32(0), deadline, regSig);

        string memory voidReason = "Customer added another item";
        bytes memory voidSig = getVoidSignature(merchant, TEST_RECEIPT_HASH, voidReason, 1, deadline);

        vm.prank(merchant);
        sellerPadiReceipt.voidReceipt(TEST_RECEIPT_HASH, voidReason, deadline, voidSig);

        // Now register new receipt referencing the voided parent receipt
        bytes memory regSig2 = getRegisterSignature(merchant, TEST_RECEIPT_HASH_2, TEST_RECEIPT_HASH, 2, deadline);
        vm.prank(merchant);
        sellerPadiReceipt.registerReceipt(TEST_RECEIPT_HASH_2, TEST_RECEIPT_HASH, deadline, regSig2);

        SellerPadiReceipt.ReceiptRecord memory record2 = sellerPadiReceipt.getReceipt(TEST_RECEIPT_HASH_2);
        assertEq(record2.parentReceiptHash, TEST_RECEIPT_HASH);
        assertEq(uint8(record2.status), uint8(SellerPadiReceipt.Status.Issued));
    }

    function test_RegisterReceipt_RevertIfParentNotVoided() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory regSig = getRegisterSignature(merchant, TEST_RECEIPT_HASH, bytes32(0), 0, deadline);

        vm.prank(merchant);
        sellerPadiReceipt.registerReceipt(TEST_RECEIPT_HASH, bytes32(0), deadline, regSig);

        // Try to reference parent receipt while it is still active (not voided)
        bytes memory regSig2 = getRegisterSignature(merchant, TEST_RECEIPT_HASH_2, TEST_RECEIPT_HASH, 1, deadline);
        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(SellerPadiReceipt.InvalidParentReceipt.selector, TEST_RECEIPT_HASH));
        sellerPadiReceipt.registerReceipt(TEST_RECEIPT_HASH_2, TEST_RECEIPT_HASH, deadline, regSig2);
    }

    function test_VoidReceipt_Success() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory regSig = getRegisterSignature(merchant, TEST_RECEIPT_HASH, bytes32(0), 0, deadline);

        vm.prank(merchant);
        sellerPadiReceipt.registerReceipt(TEST_RECEIPT_HASH, bytes32(0), deadline, regSig);

        string memory reason = "Wrong item entered";
        bytes memory voidSig = getVoidSignature(merchant, TEST_RECEIPT_HASH, reason, 1, deadline);

        vm.warp(block.timestamp + 10 minutes);
        vm.prank(merchant);
        sellerPadiReceipt.voidReceipt(TEST_RECEIPT_HASH, reason, deadline, voidSig);

        SellerPadiReceipt.ReceiptRecord memory record = sellerPadiReceipt.getReceipt(TEST_RECEIPT_HASH);
        assertEq(uint8(record.status), uint8(SellerPadiReceipt.Status.Voided));
        assertEq(record.voidedAt, uint40(block.timestamp));
        assertEq(sellerPadiReceipt.userNonces(merchant), 2);
    }

    function test_VoidReceipt_RevertIfAlreadyVoided() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory regSig = getRegisterSignature(merchant, TEST_RECEIPT_HASH, bytes32(0), 0, deadline);

        vm.prank(merchant);
        sellerPadiReceipt.registerReceipt(TEST_RECEIPT_HASH, bytes32(0), deadline, regSig);

        string memory reason = "Wrong price";
        bytes memory voidSig = getVoidSignature(merchant, TEST_RECEIPT_HASH, reason, 1, deadline);

        vm.prank(merchant);
        sellerPadiReceipt.voidReceipt(TEST_RECEIPT_HASH, reason, deadline, voidSig);

        // Try voiding again
        bytes memory voidSig2 = getVoidSignature(merchant, TEST_RECEIPT_HASH, reason, 2, deadline);
        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(SellerPadiReceipt.ReceiptAlreadyVoided.selector, TEST_RECEIPT_HASH));
        sellerPadiReceipt.voidReceipt(TEST_RECEIPT_HASH, reason, deadline, voidSig2);
    }

    function test_VoidReceipt_NonExistentReverts() public {
        uint256 deadline = block.timestamp + 1 hours;
        string memory reason = "Mistake";
        bytes memory voidSig = getVoidSignature(merchant, TEST_RECEIPT_HASH, reason, 0, deadline);

        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(SellerPadiReceipt.ReceiptNotFound.selector, TEST_RECEIPT_HASH));
        sellerPadiReceipt.voidReceipt(TEST_RECEIPT_HASH, reason, deadline, voidSig);
    }

    function test_VoidReceipt_UnauthorizedCallerReverts() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory regSig = getRegisterSignature(merchant, TEST_RECEIPT_HASH, bytes32(0), 0, deadline);

        vm.prank(merchant);
        sellerPadiReceipt.registerReceipt(TEST_RECEIPT_HASH, bytes32(0), deadline, regSig);

        string memory reason = "Malicious void attempt";
        bytes memory voidSig = getVoidSignature(otherUser, TEST_RECEIPT_HASH, reason, 0, deadline);

        vm.prank(otherUser);
        vm.expectRevert(SellerPadiReceipt.UnauthorizedMerchant.selector);
        sellerPadiReceipt.voidReceipt(TEST_RECEIPT_HASH, reason, deadline, voidSig);
    }

    function test_SetBackendSigner_OwnerOnly() public {
        address newSigner = address(0x99);

        // Non-owner reverts
        vm.prank(otherUser);
        vm.expectRevert();
        sellerPadiReceipt.setBackendSigner(newSigner);

        // Owner succeeds
        vm.prank(proxyOwner);
        sellerPadiReceipt.setBackendSigner(newSigner);
        assertEq(sellerPadiReceipt.backendSigner(), newSigner);

        // Zero address reverts
        vm.prank(proxyOwner);
        vm.expectRevert(SellerPadiReceipt.InvalidBackendSigner.selector);
        sellerPadiReceipt.setBackendSigner(address(0));
    }

    function test_UpgradePreservesState() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory regSig = getRegisterSignature(merchant, TEST_RECEIPT_HASH, bytes32(0), 0, deadline);

        vm.prank(merchant);
        sellerPadiReceipt.registerReceipt(TEST_RECEIPT_HASH, bytes32(0), deadline, regSig);

        // Deploy V2
        SellerPadiReceiptMockV2 v2Impl = new SellerPadiReceiptMockV2();

        // Upgrade
        vm.prank(proxyOwner);
        sellerPadiReceipt.upgradeToAndCall(address(v2Impl), "");

        // State is preserved
        SellerPadiReceipt.ReceiptRecord memory record = sellerPadiReceipt.getReceipt(TEST_RECEIPT_HASH);
        assertEq(record.receiptHash, TEST_RECEIPT_HASH);
        assertEq(record.merchant, merchant);
        assertEq(uint8(record.status), uint8(SellerPadiReceipt.Status.Issued));
        assertEq(sellerPadiReceipt.backendSigner(), backendSigner);

        // V2 function is callable
        SellerPadiReceiptMockV2 v2 = SellerPadiReceiptMockV2(address(sellerPadiReceipt));
        assertEq(v2.version(), "v2");
    }

    function test_UpgradeToV2_OwnerOnly() public {
        SellerPadiReceiptMockV2 v2Impl = new SellerPadiReceiptMockV2();

        vm.prank(otherUser);
        vm.expectRevert();
        sellerPadiReceipt.upgradeToAndCall(address(v2Impl), "");
    }

    // --- Merkle Batch Tests ---

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function test_AnchorReceiptBatch_Success() public {
        bytes32 leaf0 = keccak256("RECEIPT-001");
        bytes32 leaf1 = keccak256("RECEIPT-002");
        bytes32 merkleRoot = _hashPair(leaf0, leaf1);
        bytes32[] memory hashes = new bytes32[](2);
        hashes[0] = leaf0;
        hashes[1] = leaf1;
        uint32 recordCount = 2;
        uint256 deadline = block.timestamp + 1 hours;

        address relayer = address(0xAA);
        bytes memory sig = getBatchSignature(relayer, merkleRoot, recordCount, 0, deadline);

        vm.prank(relayer);
        vm.expectEmit(true, true, false, true);
        emit SellerPadiReceipt.ReceiptBatchAnchored(merkleRoot, relayer, hashes, block.timestamp);
        sellerPadiReceipt.anchorReceiptBatch(merkleRoot, hashes, deadline, sig);

        // Verify batch storage
        SellerPadiReceipt.BatchRecord memory batch = sellerPadiReceipt.getBatch(merkleRoot);
        assertEq(batch.merkleRoot, merkleRoot);
        assertEq(batch.relayer, relayer);
        assertEq(batch.recordCount, recordCount);
        assertEq(batch.anchoredAt, uint40(block.timestamp));

        // Verify Merkle inclusion proofs
        bytes32[] memory proof0 = new bytes32[](1);
        proof0[0] = leaf1;
        assertTrue(sellerPadiReceipt.verifyReceiptProof(leaf0, proof0, merkleRoot));
        assertTrue(sellerPadiReceipt.verifyProof(leaf0, proof0, merkleRoot));

        bytes32[] memory proof1 = new bytes32[](1);
        proof1[0] = leaf0;
        assertTrue(sellerPadiReceipt.verifyReceiptProof(leaf1, proof1, merkleRoot));
        assertTrue(sellerPadiReceipt.verifyProof(leaf1, proof1, merkleRoot));

        // Tampered leaf fails
        bytes32 fakeLeaf = keccak256("RECEIPT-FAKE");
        assertFalse(sellerPadiReceipt.verifyReceiptProof(fakeLeaf, proof0, merkleRoot));
        assertFalse(sellerPadiReceipt.verifyProof(fakeLeaf, proof0, merkleRoot));

        // Non-existent batch fails
        bytes32 nonExistentRoot = keccak256("UNKNOWN-ROOT");
        assertFalse(sellerPadiReceipt.verifyReceiptProof(leaf0, proof0, nonExistentRoot));
        assertFalse(sellerPadiReceipt.verifyProof(leaf0, proof0, nonExistentRoot));
    }

    function test_AnchorReceiptBatch_ZeroRootReverts() public {
        address relayer = address(0xAA);
        uint256 deadline = block.timestamp + 1 hours;
        bytes32[] memory hashes = new bytes32[](1);
        hashes[0] = keccak256("LEAF");
        bytes memory sig = getBatchSignature(relayer, bytes32(0), 1, 0, deadline);

        vm.prank(relayer);
        vm.expectRevert(SellerPadiReceipt.InvalidMerkleRoot.selector);
        sellerPadiReceipt.anchorReceiptBatch(bytes32(0), hashes, deadline, sig);
    }

    function test_AnchorReceiptBatch_ZeroCountReverts() public {
        address relayer = address(0xAA);
        bytes32 root = keccak256("SOME_ROOT");
        uint256 deadline = block.timestamp + 1 hours;
        bytes32[] memory emptyHashes = new bytes32[](0);
        bytes memory sig = getBatchSignature(relayer, root, 0, 0, deadline);

        vm.prank(relayer);
        vm.expectRevert(SellerPadiReceipt.InvalidRecordCount.selector);
        sellerPadiReceipt.anchorReceiptBatch(root, emptyHashes, deadline, sig);
    }

    function test_AnchorReceiptBatch_BatchLimitExceeded() public {
        address relayer = address(0xAA);
        bytes32 root = keccak256("OVERSIZED_ROOT");
        uint256 deadline = block.timestamp + 1 hours;
        bytes32[] memory oversizedHashes = new bytes32[](201);
        bytes memory sig = getBatchSignature(relayer, root, 201, 0, deadline);

        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(SellerPadiReceipt.BatchLimitExceeded.selector, 201, 200));
        sellerPadiReceipt.anchorReceiptBatch(root, oversizedHashes, deadline, sig);
    }

    function test_AnchorReceiptBatch_ReplayReverts() public {
        bytes32 root = keccak256("REPLAY_ROOT");
        uint32 count = 2;
        uint256 deadline = block.timestamp + 1 hours;
        address relayer = address(0xAA);
        bytes32[] memory hashes = new bytes32[](2);
        hashes[0] = keccak256("R1");
        hashes[1] = keccak256("R2");
        bytes memory sig = getBatchSignature(relayer, root, count, 0, deadline);

        vm.prank(relayer);
        sellerPadiReceipt.anchorReceiptBatch(root, hashes, deadline, sig);

        // Try registering again with the same signature -> Reverts with BatchAlreadyExists
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(SellerPadiReceipt.BatchAlreadyExists.selector, root));
        sellerPadiReceipt.anchorReceiptBatch(root, hashes, deadline, sig);
    }

    function test_AnchorReceiptBatch_RevertIfExpired() public {
        bytes32 root = keccak256("EXPIRED_ROOT");
        uint32 count = 1;
        uint256 deadline = block.timestamp - 1;
        address relayer = address(0xAA);
        bytes32[] memory hashes = new bytes32[](1);
        hashes[0] = keccak256("R1");
        bytes memory sig = getBatchSignature(relayer, root, count, 0, deadline);

        vm.prank(relayer);
        vm.expectRevert(SellerPadiReceipt.SignatureExpired.selector);
        sellerPadiReceipt.anchorReceiptBatch(root, hashes, deadline, sig);
    }

    function test_AnchorReceiptBatch_InvalidSignature() public {
        bytes32 root = keccak256("INVALID_SIG_ROOT");
        uint32 count = 1;
        uint256 deadline = block.timestamp + 1 hours;
        address relayer = address(0xAA);
        bytes32[] memory hashes = new bytes32[](1);
        hashes[0] = keccak256("R1");

        // Sign with unauthorized key
        uint256 badKey = 0x123456789;
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                relayer, root, uint256(count), uint256(0), deadline, block.chainid, address(sellerPadiReceipt)
            )
        );
        bytes32 ethSigned = MessageHashUtils.toEthSignedMessageHash(msgHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(badKey, ethSigned);
        bytes memory badSig = abi.encodePacked(r, s, v);

        vm.prank(relayer);
        vm.expectRevert(SellerPadiReceipt.InvalidSignature.selector);
        sellerPadiReceipt.anchorReceiptBatch(root, hashes, deadline, badSig);
    }

    function test_AnchorReceiptBatch_MixedLeaves() public {
        bytes32 receiptLeaf = keccak256("CANONICAL-RECEIPT-001");
        bytes32 voidLeaf = keccak256(abi.encodePacked(keccak256("RECEIPT-002"), keccak256("Customer Returned Item")));
        bytes32 merkleRoot = _hashPair(receiptLeaf, voidLeaf);
        bytes32[] memory hashes = new bytes32[](2);
        hashes[0] = receiptLeaf;
        hashes[1] = voidLeaf;
        uint32 recordCount = 2;
        uint256 deadline = block.timestamp + 1 hours;

        address relayer = address(0xAA);
        bytes memory sig = getBatchSignature(relayer, merkleRoot, recordCount, 0, deadline);

        vm.prank(relayer);
        vm.expectEmit(true, true, false, true);
        emit SellerPadiReceipt.ReceiptBatchAnchored(merkleRoot, relayer, hashes, block.timestamp);
        sellerPadiReceipt.anchorReceiptBatch(merkleRoot, hashes, deadline, sig);

        // Verify both receipt creation and void leaves verify against unified root
        bytes32[] memory proofForReceipt = new bytes32[](1);
        proofForReceipt[0] = voidLeaf;
        assertTrue(sellerPadiReceipt.verifyProof(receiptLeaf, proofForReceipt, merkleRoot));
        assertTrue(sellerPadiReceipt.verifyReceiptProof(receiptLeaf, proofForReceipt, merkleRoot));

        bytes32[] memory proofForVoid = new bytes32[](1);
        proofForVoid[0] = receiptLeaf;
        assertTrue(sellerPadiReceipt.verifyProof(voidLeaf, proofForVoid, merkleRoot));
        assertTrue(sellerPadiReceipt.verifyVoidProof(voidLeaf, proofForVoid, merkleRoot));
    }
}

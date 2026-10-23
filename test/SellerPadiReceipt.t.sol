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

    bytes32 public constant TEST_RECEIPT_HASH = keccak256("RCVR-REC-2026-0001");
    bytes32 public constant TEST_RECEIPT_HASH_2 =
        keccak256("RCVR-REC-2026-0002");

    function setUp() public {
        proxyOwner = address(this);
        merchant = address(0x11);
        otherUser = address(0x22);
        backendPrivateKey = 0xBEAF;
        backendSigner = vm.addr(backendPrivateKey);

        // Deploy implementation
        SellerPadiReceipt impl = new SellerPadiReceipt();

        // Encode initializer
        bytes memory initData = abi.encodeWithSelector(
            SellerPadiReceipt.initialize.selector,
            backendSigner
        );

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
                merchantAddr,
                receiptHash,
                parentReceiptHash,
                nonce,
                deadline,
                block.chainid,
                address(sellerPadiReceipt)
            )
        );
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(
            messageHash
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            backendPrivateKey,
            ethSignedMessageHash
        );
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
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(
            messageHash
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            backendPrivateKey,
            ethSignedMessageHash
        );
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
        bytes memory sig = getRegisterSignature(
            merchant,
            TEST_RECEIPT_HASH,
            bytes32(0),
            0,
            deadline
        );

        vm.prank(merchant);
        sellerPadiReceipt.registerReceipt(
            TEST_RECEIPT_HASH,
            bytes32(0),
            deadline,
            sig
        );

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
        bytes memory sig = getRegisterSignature(
            merchant,
            TEST_RECEIPT_HASH,
            bytes32(0),
            0,
            deadline
        );

        vm.prank(merchant);
        vm.expectRevert(SellerPadiReceipt.SignatureExpired.selector);
        sellerPadiReceipt.registerReceipt(
            TEST_RECEIPT_HASH,
            bytes32(0),
            deadline,
            sig
        );
    }

    function test_RegisterReceipt_ZeroHashReverts() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = getRegisterSignature(
            merchant,
            bytes32(0),
            bytes32(0),
            0,
            deadline
        );

        vm.prank(merchant);
        vm.expectRevert(SellerPadiReceipt.InvalidReceiptHash.selector);
        sellerPadiReceipt.registerReceipt(
            bytes32(0),
            bytes32(0),
            deadline,
            sig
        );
    }

    function test_RegisterReceipt_InvalidSignature() public {
        uint256 deadline = block.timestamp + 1 hours;
        // Sign with a different key
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                merchant,
                TEST_RECEIPT_HASH,
                bytes32(0),
                uint256(0),
                deadline,
                block.chainid,
                address(sellerPadiReceipt)
            )
        );
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(
            messageHash
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x9999, ethSignedMessageHash);
        bytes memory invalidSig = abi.encodePacked(r, s, v);

        vm.prank(merchant);
        vm.expectRevert(SellerPadiReceipt.InvalidSignature.selector);
        sellerPadiReceipt.registerReceipt(
            TEST_RECEIPT_HASH,
            bytes32(0),
            deadline,
            invalidSig
        );
    }

    function test_RegisterReceipt_ReplayReverts() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = getRegisterSignature(
            merchant,
            TEST_RECEIPT_HASH,
            bytes32(0),
            0,
            deadline
        );

        vm.prank(merchant);
        sellerPadiReceipt.registerReceipt(
            TEST_RECEIPT_HASH,
            bytes32(0),
            deadline,
            sig
        );

        // Attempt to replay with same signature
        vm.prank(merchant);
        vm.expectRevert(SellerPadiReceipt.InvalidSignature.selector);
        sellerPadiReceipt.registerReceipt(
            TEST_RECEIPT_HASH_2,
            bytes32(0),
            deadline,
            sig
        );
    }

    function test_RegisterReceipt_AlreadyExists() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = getRegisterSignature(
            merchant,
            TEST_RECEIPT_HASH,
            bytes32(0),
            0,
            deadline
        );

        vm.prank(merchant);
        sellerPadiReceipt.registerReceipt(
            TEST_RECEIPT_HASH,
            bytes32(0),
            deadline,
            sig
        );

        // Try registering exact same hash with new nonce
        bytes memory sig2 = getRegisterSignature(
            merchant,
            TEST_RECEIPT_HASH,
            bytes32(0),
            1,
            deadline
        );
        vm.prank(merchant);
        vm.expectRevert(
            abi.encodeWithSelector(
                SellerPadiReceipt.ReceiptAlreadyExists.selector,
                TEST_RECEIPT_HASH
            )
        );
        sellerPadiReceipt.registerReceipt(
            TEST_RECEIPT_HASH,
            bytes32(0),
            deadline,
            sig2
        );
    }

    function test_RegisterReceipt_WithParentVoidedReceipt() public {
        // First register and void parent receipt
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory regSig = getRegisterSignature(
            merchant,
            TEST_RECEIPT_HASH,
            bytes32(0),
            0,
            deadline
        );

        vm.prank(merchant);
        sellerPadiReceipt.registerReceipt(
            TEST_RECEIPT_HASH,
            bytes32(0),
            deadline,
            regSig
        );

        string memory voidReason = "Customer added another item";
        bytes memory voidSig = getVoidSignature(
            merchant,
            TEST_RECEIPT_HASH,
            voidReason,
            1,
            deadline
        );

        vm.prank(merchant);
        sellerPadiReceipt.voidReceipt(
            TEST_RECEIPT_HASH,
            voidReason,
            deadline,
            voidSig
        );

        // Now register new receipt referencing the voided parent receipt
        bytes memory regSig2 = getRegisterSignature(
            merchant,
            TEST_RECEIPT_HASH_2,
            TEST_RECEIPT_HASH,
            2,
            deadline
        );
        vm.prank(merchant);
        sellerPadiReceipt.registerReceipt(
            TEST_RECEIPT_HASH_2,
            TEST_RECEIPT_HASH,
            deadline,
            regSig2
        );

        SellerPadiReceipt.ReceiptRecord memory record2 = sellerPadiReceipt.getReceipt(TEST_RECEIPT_HASH_2);
        assertEq(record2.parentReceiptHash, TEST_RECEIPT_HASH);
        assertEq(uint8(record2.status), uint8(SellerPadiReceipt.Status.Issued));
    }

    function test_RegisterReceipt_RevertIfParentNotVoided() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory regSig = getRegisterSignature(
            merchant,
            TEST_RECEIPT_HASH,
            bytes32(0),
            0,
            deadline
        );

        vm.prank(merchant);
        sellerPadiReceipt.registerReceipt(
            TEST_RECEIPT_HASH,
            bytes32(0),
            deadline,
            regSig
        );

        // Try to reference parent receipt while it is still active (not voided)
        bytes memory regSig2 = getRegisterSignature(
            merchant,
            TEST_RECEIPT_HASH_2,
            TEST_RECEIPT_HASH,
            1,
            deadline
        );
        vm.prank(merchant);
        vm.expectRevert(
            abi.encodeWithSelector(
                SellerPadiReceipt.InvalidParentReceipt.selector,
                TEST_RECEIPT_HASH
            )
        );
        sellerPadiReceipt.registerReceipt(
            TEST_RECEIPT_HASH_2,
            TEST_RECEIPT_HASH,
            deadline,
            regSig2
        );
    }

    function test_VoidReceipt_Success() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory regSig = getRegisterSignature(
            merchant,
            TEST_RECEIPT_HASH,
            bytes32(0),
            0,
            deadline
        );

        vm.prank(merchant);
        sellerPadiReceipt.registerReceipt(
            TEST_RECEIPT_HASH,
            bytes32(0),
            deadline,
            regSig
        );

        string memory reason = "Wrong item entered";
        bytes memory voidSig = getVoidSignature(
            merchant,
            TEST_RECEIPT_HASH,
            reason,
            1,
            deadline
        );

        vm.warp(block.timestamp + 10 minutes);
        vm.prank(merchant);
        sellerPadiReceipt.voidReceipt(
            TEST_RECEIPT_HASH,
            reason,
            deadline,
            voidSig
        );

        SellerPadiReceipt.ReceiptRecord memory record = sellerPadiReceipt.getReceipt(TEST_RECEIPT_HASH);
        assertEq(uint8(record.status), uint8(SellerPadiReceipt.Status.Voided));
        assertEq(record.voidedAt, uint40(block.timestamp));
        assertEq(sellerPadiReceipt.userNonces(merchant), 2);
    }

    function test_VoidReceipt_RevertIfAlreadyVoided() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory regSig = getRegisterSignature(
            merchant,
            TEST_RECEIPT_HASH,
            bytes32(0),
            0,
            deadline
        );

        vm.prank(merchant);
        sellerPadiReceipt.registerReceipt(
            TEST_RECEIPT_HASH,
            bytes32(0),
            deadline,
            regSig
        );

        string memory reason = "Wrong price";
        bytes memory voidSig = getVoidSignature(
            merchant,
            TEST_RECEIPT_HASH,
            reason,
            1,
            deadline
        );

        vm.prank(merchant);
        sellerPadiReceipt.voidReceipt(
            TEST_RECEIPT_HASH,
            reason,
            deadline,
            voidSig
        );

        // Try voiding again
        bytes memory voidSig2 = getVoidSignature(
            merchant,
            TEST_RECEIPT_HASH,
            reason,
            2,
            deadline
        );
        vm.prank(merchant);
        vm.expectRevert(
            abi.encodeWithSelector(
                SellerPadiReceipt.ReceiptAlreadyVoided.selector,
                TEST_RECEIPT_HASH
            )
        );
        sellerPadiReceipt.voidReceipt(
            TEST_RECEIPT_HASH,
            reason,
            deadline,
            voidSig2
        );
    }

    function test_VoidReceipt_NonExistentReverts() public {
        uint256 deadline = block.timestamp + 1 hours;
        string memory reason = "Mistake";
        bytes memory voidSig = getVoidSignature(
            merchant,
            TEST_RECEIPT_HASH,
            reason,
            0,
            deadline
        );

        vm.prank(merchant);
        vm.expectRevert(
            abi.encodeWithSelector(
                SellerPadiReceipt.ReceiptNotFound.selector,
                TEST_RECEIPT_HASH
            )
        );
        sellerPadiReceipt.voidReceipt(
            TEST_RECEIPT_HASH,
            reason,
            deadline,
            voidSig
        );
    }

    function test_VoidReceipt_UnauthorizedCallerReverts() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory regSig = getRegisterSignature(
            merchant,
            TEST_RECEIPT_HASH,
            bytes32(0),
            0,
            deadline
        );

        vm.prank(merchant);
        sellerPadiReceipt.registerReceipt(
            TEST_RECEIPT_HASH,
            bytes32(0),
            deadline,
            regSig
        );

        string memory reason = "Malicious void attempt";
        bytes memory voidSig = getVoidSignature(
            otherUser,
            TEST_RECEIPT_HASH,
            reason,
            0,
            deadline
        );

        vm.prank(otherUser);
        vm.expectRevert(SellerPadiReceipt.UnauthorizedMerchant.selector);
        sellerPadiReceipt.voidReceipt(
            TEST_RECEIPT_HASH,
            reason,
            deadline,
            voidSig
        );
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
        bytes memory regSig = getRegisterSignature(
            merchant,
            TEST_RECEIPT_HASH,
            bytes32(0),
            0,
            deadline
        );

        vm.prank(merchant);
        sellerPadiReceipt.registerReceipt(
            TEST_RECEIPT_HASH,
            bytes32(0),
            deadline,
            regSig
        );

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
        SellerPadiReceiptMockV2 v2 = SellerPadiReceiptMockV2(
            address(sellerPadiReceipt)
        );
        assertEq(v2.version(), "v2");
    }

    function test_UpgradeToV2_OwnerOnly() public {
        SellerPadiReceiptMockV2 v2Impl = new SellerPadiReceiptMockV2();

        vm.prank(otherUser);
        vm.expectRevert();
        sellerPadiReceipt.upgradeToAndCall(address(v2Impl), "");
    }
}

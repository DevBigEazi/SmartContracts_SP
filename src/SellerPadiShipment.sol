// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title SellerPadiShipment
 * @notice A decentralized UUPS-upgradeable shipment verification and chain of custody registry.
 * @dev Tracks shipment states and validates status transitions using cryptographically signed messages.
 */
contract SellerPadiShipment is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    // --- Enums ---
    enum Status {
        Created,
        InTransit,
        Delivered,
        Verified,
        Disputed,
        ReturnTransit,
        ReturnedToStore,
        Resolved
    }

    // --- Structs ---
    // Gas-optimized struct layout
    struct Shipment {
        bytes32 packageId;
        bytes32 packageHash; // keccak256(packageId, innerSecretHash)
        address shipper;
        address currentHandler;
        Status status;
        uint40 lastUpdated;
    }

    struct BatchRecord {
        bytes32 merkleRoot; // keccak256 root of the Merkle tree of batched package dispatch hashes
        address relayer; // Address of the relayer submitting the batch
        uint32 recordCount; // Number of shipments anchored in this batch
        uint40 anchoredAt; // Block timestamp when the batch was anchored
    }

    // --- State Variables ---
    address public backendSigner;
    mapping(bytes32 => Shipment) private _shipments;
    mapping(address => uint256) public userNonces;
    mapping(bytes32 => BatchRecord) private _batches;

    // --- Events ---
    event ShipmentRegistered(
        bytes32 indexed packageId, address indexed shipper, bytes32 packageHash, uint256 timestamp
    );
    event ShipmentHandover(bytes32 indexed packageId, address indexed nextHandler, uint256 timestamp);
    event ShipmentVerified(bytes32 indexed packageId, uint256 timestamp);
    event ShipmentDisputed(bytes32 indexed packageId, string reason, uint256 timestamp);
    event ShipmentReturnHandover(bytes32 indexed packageId, address indexed returnHandler, uint256 timestamp);
    event ShipmentReturnedToStore(bytes32 indexed packageId, address indexed storeBranch, uint256 timestamp);
    event ShipmentResolved(bytes32 indexed packageId, string resolutionType, uint256 timestamp);
    event ShipmentRedispatched(
        bytes32 indexed packageId, bytes32 newPackageHash, address indexed nextHandler, uint256 timestamp
    );
    event ShipmentBatchRegistered(
        bytes32 indexed merkleRoot, address indexed relayer, uint32 recordCount, uint256 timestamp
    );
    event BackendSignerChanged(address indexed oldSigner, address indexed newSigner);

    // --- Custom Errors ---
    error ShipmentNotFound(bytes32 packageId);
    error ShipmentAlreadyExists(bytes32 packageId);
    error BatchAlreadyExists(bytes32 merkleRoot);
    error BatchNotFound(bytes32 merkleRoot);
    error InvalidStatusTransition(bytes32 packageId, Status currentStatus, Status targetStatus);
    error InvalidPackageHash();
    error InvalidMerkleRoot();
    error InvalidRecordCount();
    error InvalidShipperAddress();
    error InvalidHandlerAddress();
    error InvalidBackendSigner();
    error SignatureExpired();
    error InvalidSignature();
    error InvalidSecret();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the UUPS upgradeable contract.
     * @param _backendSigner The address of the off-chain witness signing key.
     */
    function initialize(address _backendSigner) public initializer {
        __Ownable_init(msg.sender);
        if (_backendSigner == address(0)) {
            revert InvalidBackendSigner();
        }
        backendSigner = _backendSigner;
    }

    // --- External Functions ---

    /**
     * @notice Registers a new shipment with witness signature validation.
     * @param packageId The unique ID of the package.
     * @param packageHash The hash of the secret code required to claim the package.
     * @param deadline The signature expiration timestamp.
     * @param signature The cryptographic signature from the backend signer.
     */
    function registerShipment(bytes32 packageId, bytes32 packageHash, uint256 deadline, bytes calldata signature)
        external
    {
        if (block.timestamp > deadline) revert SignatureExpired();
        if (packageHash == bytes32(0)) revert InvalidPackageHash();
        if (_shipments[packageId].packageId != bytes32(0)) {
            revert ShipmentAlreadyExists(packageId);
        }

        address shipper = msg.sender;
        uint256 nonce = userNonces[shipper];
        bytes32 messageHash =
            keccak256(abi.encodePacked(shipper, packageId, packageHash, nonce, deadline, block.chainid, address(this)));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        if (ECDSA.recover(ethSignedMessageHash, signature) != backendSigner) {
            revert InvalidSignature();
        }

        userNonces[shipper] = nonce + 1;
        uint40 timestamp = uint40(block.timestamp);

        _shipments[packageId] = Shipment({
            packageId: packageId,
            packageHash: packageHash,
            shipper: shipper,
            currentHandler: address(0),
            status: Status.Created,
            lastUpdated: timestamp
        });

        emit ShipmentRegistered(packageId, shipper, packageHash, timestamp);
    }

    /**
     * @notice Anchors a cryptographic Merkle root representing a batch of dispatched packages.
     * @dev Reduces on-chain gas costs by ~99% by anchoring hundreds of shipments in a single transaction.
     * @param merkleRoot The keccak256 root of the Merkle tree formed by batched package hashes.
     * @param recordCount The count of shipment records included in this batch.
     * @param deadline The signature expiration timestamp.
     * @param signature The cryptographic witness signature from the backend signer.
     */
    function registerShipmentBatch(bytes32 merkleRoot, uint32 recordCount, uint256 deadline, bytes calldata signature)
        external
    {
        if (block.timestamp > deadline) revert SignatureExpired();
        if (merkleRoot == bytes32(0)) revert InvalidMerkleRoot();
        if (recordCount == 0) revert InvalidRecordCount();
        if (_batches[merkleRoot].merkleRoot != bytes32(0)) {
            revert BatchAlreadyExists(merkleRoot);
        }

        address relayer = msg.sender;
        uint256 nonce = userNonces[relayer];

        bytes32 messageHash = keccak256(
            abi.encodePacked(relayer, merkleRoot, uint256(recordCount), nonce, deadline, block.chainid, address(this))
        );
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        if (ECDSA.recover(ethSignedMessageHash, signature) != backendSigner) {
            revert InvalidSignature();
        }

        userNonces[relayer] = nonce + 1;
        uint40 timestamp = uint40(block.timestamp);

        _batches[merkleRoot] =
            BatchRecord({merkleRoot: merkleRoot, relayer: relayer, recordCount: recordCount, anchoredAt: timestamp});

        emit ShipmentBatchRegistered(merkleRoot, relayer, recordCount, timestamp);
    }

    /**
     * @notice Logs a dispatch rider / delivery handover milestone with signature verification.
     * @param packageId The unique ID of the package.
     * @param nextHandler The handler taking custody of the shipment.
     * @param deadline The signature expiration timestamp.
     * @param signature The cryptographic signature from the backend signer.
     */
    function logHandover(bytes32 packageId, address nextHandler, uint256 deadline, bytes calldata signature) external {
        if (block.timestamp > deadline) revert SignatureExpired();
        if (nextHandler == address(0)) revert InvalidHandlerAddress();

        Shipment storage shipment = _shipments[packageId];
        if (shipment.packageId == bytes32(0)) {
            revert ShipmentNotFound(packageId);
        }
        if (shipment.status != Status.Created) {
            revert InvalidStatusTransition(packageId, shipment.status, Status.InTransit);
        }

        address operator = msg.sender;
        uint256 nonce = userNonces[operator];
        bytes32 messageHash =
            keccak256(abi.encodePacked(operator, packageId, nextHandler, nonce, deadline, block.chainid, address(this)));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        if (ECDSA.recover(ethSignedMessageHash, signature) != backendSigner) {
            revert InvalidSignature();
        }

        userNonces[operator] = nonce + 1;
        uint40 timestamp = uint40(block.timestamp);

        shipment.currentHandler = nextHandler;
        shipment.status = Status.InTransit;
        shipment.lastUpdated = timestamp;

        emit ShipmentHandover(packageId, nextHandler, timestamp);
    }

    /**
     * @notice Verifies delivery by supplying the correct scratch-off secret.
     * @param packageId The unique ID of the package.
     * @param innerSecret The secret code found underneath the scratch-off layer.
     * @param deadline The signature expiration timestamp.
     * @param signature The cryptographic signature from the backend signer.
     */
    function verifyDelivery(bytes32 packageId, string calldata innerSecret, uint256 deadline, bytes calldata signature)
        external
    {
        if (block.timestamp > deadline) revert SignatureExpired();

        Shipment storage shipment = _shipments[packageId];
        if (shipment.packageId == bytes32(0)) {
            revert ShipmentNotFound(packageId);
        }
        if (shipment.status != Status.InTransit) {
            revert InvalidStatusTransition(packageId, shipment.status, Status.Verified);
        }

        if (keccak256(abi.encodePacked(packageId, innerSecret)) != shipment.packageHash) {
            revert InvalidSecret();
        }

        address caller = msg.sender;
        uint256 nonce = userNonces[caller];
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                caller, packageId, keccak256(bytes(innerSecret)), nonce, deadline, block.chainid, address(this)
            )
        );
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        if (ECDSA.recover(ethSignedMessageHash, signature) != backendSigner) {
            revert InvalidSignature();
        }

        userNonces[caller] = nonce + 1;
        uint40 timestamp = uint40(block.timestamp);

        shipment.status = Status.Verified;
        shipment.lastUpdated = timestamp;

        emit ShipmentVerified(packageId, timestamp);
    }

    /**
     * @notice Disputes package delivery (e.g. tampered sticker or empty package).
     * @param packageId The unique ID of the package.
     * @param reason The dispute description.
     * @param deadline The signature expiration timestamp.
     * @param signature The cryptographic signature from the backend signer.
     */
    function disputeDelivery(bytes32 packageId, string calldata reason, uint256 deadline, bytes calldata signature)
        external
    {
        if (block.timestamp > deadline) revert SignatureExpired();

        Shipment storage shipment = _shipments[packageId];
        if (shipment.packageId == bytes32(0)) {
            revert ShipmentNotFound(packageId);
        }
        if (shipment.status != Status.InTransit) {
            revert InvalidStatusTransition(packageId, shipment.status, Status.Disputed);
        }

        address caller = msg.sender;
        uint256 nonce = userNonces[caller];
        bytes32 messageHash = keccak256(
            abi.encodePacked(caller, packageId, keccak256(bytes(reason)), nonce, deadline, block.chainid, address(this))
        );
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        if (ECDSA.recover(ethSignedMessageHash, signature) != backendSigner) {
            revert InvalidSignature();
        }

        userNonces[caller] = nonce + 1;
        uint40 timestamp = uint40(block.timestamp);

        shipment.status = Status.Disputed;
        shipment.lastUpdated = timestamp;

        emit ShipmentDisputed(packageId, reason, timestamp);
    }

    /**
     * @notice Hands a disputed package back to a dispatch rider for return transit.
     * @param packageId The unique ID of the package.
     * @param rider The dispatch rider taking custody of the returned parcel.
     * @param deadline The signature expiration timestamp.
     * @param signature The cryptographic signature from the backend signer.
     */
    function handoverReturn(bytes32 packageId, address rider, uint256 deadline, bytes calldata signature) external {
        if (block.timestamp > deadline) revert SignatureExpired();
        if (rider == address(0)) revert InvalidHandlerAddress();

        Shipment storage shipment = _shipments[packageId];
        if (shipment.packageId == bytes32(0)) {
            revert ShipmentNotFound(packageId);
        }
        if (shipment.status != Status.Disputed && shipment.status != Status.ReturnTransit) {
            revert InvalidStatusTransition(packageId, shipment.status, Status.ReturnTransit);
        }

        address caller = msg.sender;
        uint256 nonce = userNonces[caller];
        bytes32 messageHash =
            keccak256(abi.encodePacked(caller, packageId, rider, nonce, deadline, block.chainid, address(this)));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        if (ECDSA.recover(ethSignedMessageHash, signature) != backendSigner) {
            revert InvalidSignature();
        }

        userNonces[caller] = nonce + 1;
        uint40 timestamp = uint40(block.timestamp);

        shipment.currentHandler = rider;
        shipment.status = Status.ReturnTransit;
        shipment.lastUpdated = timestamp;

        emit ShipmentReturnHandover(packageId, rider, timestamp);
    }

    /**
     * @notice Confirms physical receipt of a returned package at the merchant's store branch.
     * @param packageId The unique ID of the package.
     * @param deadline The signature expiration timestamp.
     * @param signature The cryptographic signature from the backend signer.
     */
    function confirmStoreReturn(bytes32 packageId, uint256 deadline, bytes calldata signature) external {
        if (block.timestamp > deadline) revert SignatureExpired();

        Shipment storage shipment = _shipments[packageId];
        if (shipment.packageId == bytes32(0)) {
            revert ShipmentNotFound(packageId);
        }
        if (shipment.status != Status.ReturnTransit) {
            revert InvalidStatusTransition(packageId, shipment.status, Status.ReturnedToStore);
        }

        address caller = msg.sender;
        uint256 nonce = userNonces[caller];
        bytes32 messageHash =
            keccak256(abi.encodePacked(caller, packageId, nonce, deadline, block.chainid, address(this)));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        if (ECDSA.recover(ethSignedMessageHash, signature) != backendSigner) {
            revert InvalidSignature();
        }

        userNonces[caller] = nonce + 1;
        uint40 timestamp = uint40(block.timestamp);

        shipment.currentHandler = shipment.shipper;
        shipment.status = Status.ReturnedToStore;
        shipment.lastUpdated = timestamp;

        emit ShipmentReturnedToStore(packageId, shipment.shipper, timestamp);
    }

    /**
     * @notice Concludes dispute settlement at the store (Path A: refund issued / goods restocked).
     * @param packageId The unique ID of the package.
     * @param resolutionType Description of settlement (e.g. "Refunded", "Restocked").
     * @param deadline The signature expiration timestamp.
     * @param signature The cryptographic signature from the backend signer.
     */
    function resolveDispute(
        bytes32 packageId,
        string calldata resolutionType,
        uint256 deadline,
        bytes calldata signature
    ) external {
        if (block.timestamp > deadline) revert SignatureExpired();

        Shipment storage shipment = _shipments[packageId];
        if (shipment.packageId == bytes32(0)) {
            revert ShipmentNotFound(packageId);
        }
        if (shipment.status != Status.ReturnedToStore) {
            revert InvalidStatusTransition(packageId, shipment.status, Status.Resolved);
        }

        address caller = msg.sender;
        uint256 nonce = userNonces[caller];
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                caller, packageId, keccak256(bytes(resolutionType)), nonce, deadline, block.chainid, address(this)
            )
        );
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        if (ECDSA.recover(ethSignedMessageHash, signature) != backendSigner) {
            revert InvalidSignature();
        }

        userNonces[caller] = nonce + 1;
        uint40 timestamp = uint40(block.timestamp);

        shipment.status = Status.Resolved;
        shipment.lastUpdated = timestamp;

        emit ShipmentResolved(packageId, resolutionType, timestamp);
    }

    /**
     * @notice Re-dispatches a replacement package from the store with a fresh scratch-off PIN (Path B).
     * @param packageId The unique ID of the package.
     * @param newPackageHash The hash of the new scratch-off secret PIN for redelivery.
     * @param nextHandler The dispatch rider taking custody of the replacement parcel.
     * @param deadline The signature expiration timestamp.
     * @param signature The cryptographic signature from the backend signer.
     */
    function redispatchShipment(
        bytes32 packageId,
        bytes32 newPackageHash,
        address nextHandler,
        uint256 deadline,
        bytes calldata signature
    ) external {
        if (block.timestamp > deadline) revert SignatureExpired();
        if (newPackageHash == bytes32(0)) revert InvalidPackageHash();
        if (nextHandler == address(0)) revert InvalidHandlerAddress();

        Shipment storage shipment = _shipments[packageId];
        if (shipment.packageId == bytes32(0)) {
            revert ShipmentNotFound(packageId);
        }
        if (shipment.status != Status.ReturnedToStore) {
            revert InvalidStatusTransition(packageId, shipment.status, Status.InTransit);
        }

        address caller = msg.sender;
        uint256 nonce = userNonces[caller];
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                caller, packageId, newPackageHash, nextHandler, nonce, deadline, block.chainid, address(this)
            )
        );
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        if (ECDSA.recover(ethSignedMessageHash, signature) != backendSigner) {
            revert InvalidSignature();
        }

        userNonces[caller] = nonce + 1;
        uint40 timestamp = uint40(block.timestamp);

        shipment.packageHash = newPackageHash;
        shipment.currentHandler = nextHandler;
        shipment.status = Status.InTransit;
        shipment.lastUpdated = timestamp;

        emit ShipmentRedispatched(packageId, newPackageHash, nextHandler, timestamp);
    }

    /**
     * @notice Configures a new backend signer key. Can only be called by the owner.
     * @param _newBackendSigner The new backend signer address.
     */
    function setBackendSigner(address _newBackendSigner) external onlyOwner {
        if (_newBackendSigner == address(0)) {
            revert InvalidBackendSigner();
        }
        address oldSigner = backendSigner;
        backendSigner = _newBackendSigner;
        emit BackendSignerChanged(oldSigner, _newBackendSigner);
    }

    /**
     * @notice Retrieves shipment details.
     * @param packageId The ID of the shipment.
     * @return The shipment structure.
     */
    function getShipment(bytes32 packageId) external view returns (Shipment memory) {
        Shipment memory shipment = _shipments[packageId];
        if (shipment.packageId == bytes32(0)) {
            revert ShipmentNotFound(packageId);
        }
        return shipment;
    }

    /**
     * @notice Retrieves batch record details.
     * @param merkleRoot The Merkle root hash of the batch.
     * @return The BatchRecord structure.
     */
    function getBatch(bytes32 merkleRoot) external view returns (BatchRecord memory) {
        BatchRecord memory batch = _batches[merkleRoot];
        if (batch.merkleRoot == bytes32(0)) {
            revert BatchNotFound(merkleRoot);
        }
        return batch;
    }

    /**
     * @notice Verifies whether a specific package hash is cryptographically included in an anchored batch.
     * @param packageHash The hash of the package (keccak256(packageId, innerSecretHash)).
     * @param proof Array of sibling branch hashes leading up to the Merkle root.
     * @param merkleRoot The anchored batch Merkle root.
     * @return True if the cryptographic inclusion proof is valid.
     */
    function verifyShipmentProof(bytes32 packageHash, bytes32[] calldata proof, bytes32 merkleRoot)
        external
        view
        returns (bool)
    {
        if (_batches[merkleRoot].merkleRoot == bytes32(0)) {
            return false;
        }
        return MerkleProof.verify(proof, merkleRoot, packageHash);
    }

    // --- UUPS Upgrade Authorization ---
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // --- Storage Gap for Future Upgrades (50 - 1 used by _batches) ---
    uint256[49] private __gap;
}

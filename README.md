# SellerPadi Smart Contracts — Electroneum Smart Chain

**SellerPadi** is a paperless merchant operating system and trust protocol built for retailers, SMEs, and commercial dispatchers. These smart contracts anchor tamper-proof digital sales receipts, audit trails, and logistics package handover verifications onto **Electroneum Smart Chain (ETN-SC)**, harnessing fast EVM transaction finality and minimal gas costs for real-time counter checkouts.

---

## Architecture Overview

SellerPadi's on-chain architecture utilizes the **ERC-1967 UUPS (Universal Upgradeable Proxy Standard)** pattern with backend cryptographic signer witness verification:

1. **`SellerPadiReceipt.sol`**:
   - Anchors SHA-256 hashes of digital sales receipts individually or in gas-optimized Merkle batches.
   - **Unified Merkle Root Batching**: Supports `anchorReceiptBatch(merkleRoot, hashes, deadline, signature)` to anchor 100+ receipts and voids in a single transaction, passing all item hashes in calldata for public block explorer transparency.
   - **Cryptographic Inclusion Verification**: Stateless inclusion verification via `verifyReceiptProof(receiptHash, proof, merkleRoot)`, `verifyVoidProof(voidLeaf, proof, merkleRoot)`, and general `verifyProof(leaf, proof, merkleRoot)`.
   - Enforces audit-safe voiding controls (only the issuing merchant/cashier can void a receipt with a mandatory reason string).
   - Manages store credit settlement records on-chain.
   - Gasless customer and merchant experience: uses backend witness signatures with nonce tracking to prevent replay attacks.

2. **`SellerPadiShipment.sol`**:
   - Manages the lifecycle of tracked package dispatches (`Created` → `InTransit` → `Delivered` → `Verified` / `Disputed` → `ReturnTransit` → `ReturnedToStore` → `Resolved` or `InTransit`).
   - **Unified Merkle Root Batching**: Supports `anchorShipmentBatch(merkleRoot, hashes, deadline, signature)` to anchor bulk dispatches and milestone handovers in a single transaction, passing all item hashes in calldata for public block explorer transparency.
   - **Cryptographic Inclusion Verification**: Stateless inclusion verification via `verifyShipmentProof(packageHash, proof, merkleRoot)`, `verifyMilestoneProof(milestoneLeaf, proof, merkleRoot)`, and general `verifyProof(leaf, proof, merkleRoot)`.
   - Supports reverse logistics: disputed packages transition through return rider handover (`ReturnTransit`) and store return confirmation (`ReturnedToStore`).
   - Store settlement branches: Path A resolves the dispute (`Resolved`), while Path B re-dispatches fresh replacement goods (`InTransit`) with a new scratch-off secret PIN (`newPackageHash`) and new rider assignment.
   - Integrates dual-layer physical QR labels with scratch-off inner PIN verifications (`SP-XXXX`).
   - Enforces cryptographic proof of physical custody transfer upon customer and store handovers.

---

## Development & Testing with Foundry

Foundry is a blazing fast, portable toolkit for EVM application development written in Rust.

### Prerequisites

Ensure [Foundry](https://getfoundry.sh/) is installed:

```shell
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Build

Compile the Solidity smart contracts:

```shell
forge build
```

### Test

Execute the comprehensive Foundry test suite:

```shell
forge test -vv
```

### Gas Snapshots

Generate gas usage benchmarks:

```shell
forge snapshot
```

---

## Deployment & Verification

Deployments are executed using Foundry's encrypted keystore accounts (`cast wallet`) to ensure private keys are never stored in plaintext.

### 1. Electroneum Testnet (Chain ID `5201420`)

Deploy implementation and UUPS proxy contracts to Electroneum Testnet:

```shell
# Deploy SellerPadiReceipt (Implementation + Proxy)
forge script scripts/SellerPadiReceipt.s.sol:SellerPadiReceiptScript \
  --rpc-url electroneum-testnet \
  --account deployer \
  --broadcast \
  --verify

# Deploy SellerPadiShipment (Implementation + Proxy)
forge script scripts/SellerPadiShipment.s.sol:SellerPadiShipmentScript \
  --rpc-url electroneum-testnet \
  --account deployer \
  --broadcast \
  --verify
```

### 2. Electroneum Mainnet (Chain ID `52014`)

Deploy to Electroneum Smart Chain Mainnet:

```shell
forge script scripts/SellerPadiReceipt.s.sol:SellerPadiReceiptScript \
  --rpc-url electroneum \
  --account myWallet \
  --broadcast \
  --verify

forge script scripts/SellerPadiShipment.s.sol:SellerPadiShipmentScript \
  --rpc-url electroneum \
  --account myWallet \
  --broadcast \
  --verify
```

### 3. Upgrading UUPS Implementation Contracts

When deploying upgraded contract logic with new features, deploy the new implementation and upgrade the UUPS proxy:

```shell
# Upgrade SellerPadiReceipt Implementation
forge script script/UpgradeSellerPadiReceipt.s.sol:UpgradeSellerPadiReceiptScript \
  --rpc-url electroneum-testnet \
  --account deployer \
  --broadcast \
  --verify

# Upgrade SellerPadiShipment Implementation
forge script script/UpgradeSellerPadiShipment.s.sol:UpgradeSellerPadiShipmentScript \
  --rpc-url electroneum-testnet \
  --account deployer \
  --broadcast \
  --verify
```

### 4. Contract Verification on Electroneum Block Explorer

Electroneum operates a Blockscout-compatible block explorer. Verify deployed contracts using `forge verify-contract` with the `--verifier blockscout` engine:

```shell
# 1. Verify SellerPadiReceipt Implementation
forge verify-contract 0xA8E042374a2b2f5f06CC87455dAEfD614978d526 \
  src/SellerPadiReceipt.sol:SellerPadiReceipt \
  --verifier blockscout \
  --verifier-url "https://blockexplorer.electroneum.com/api?"

# 2. Verify SellerPadiShipment Implementation
forge verify-contract 0xE25b39D09CA340a966a89f71E91BAC974c400f55 \
  src/SellerPadiShipment.sol:SellerPadiShipment \
  --verifier blockscout \
  --verifier-url "https://blockexplorer.electroneum.com/api?"

# 3. Verify SellerPadiReceipt Proxy
forge verify-contract 0x44E0A4020eD2bf00C99047A449775c68a9E0C578 \
  lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
  --constructor-args $(cast abi-encode "constructor(address,bytes)" 0xA8E042374a2b2f5f06CC87455dAEfD614978d526 0xc4d66de80000000000000000000000002755f9b4fe69d78c51271e81e03c1f865e92c045) \
  --verifier blockscout \
  --verifier-url "https://blockexplorer.electroneum.com/api?"

# 4. Verify SellerPadiShipment Proxy
forge verify-contract 0x040BEc94Dd3Cb4C9D42c6b7896D32aEb3E3C89F5 \
  lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
  --constructor-args $(cast abi-encode "constructor(address,bytes)" 0xE25b39D09CA340a966a89f71E91BAC974c400f55 0xc4d66de80000000000000000000000002755f9b4fe69d78c51271e81e03c1f865e92c045) \
  --verifier blockscout \
  --verifier-url "https://blockexplorer.electroneum.com/api?"
```

---

## Contract Addresses

### Electroneum Testnet (Chain ID `5201420`)

- **Block Explorer:** [https://testnet-blockexplorer.electroneum.com](https://testnet-blockexplorer.electroneum.com)
- **SellerPadiReceipt Proxy:** [`0x54D4DF856e3D18966D916358dE69408b973AA09E`](https://testnet-blockexplorer.electroneum.com/address/0x54D4DF856e3D18966D916358dE69408b973AA09E)
- **SellerPadiReceipt Implementation:** [`0x50bc20b7df9e564f7A86e7C4Bce5Ab4C8bDA04BD`](https://testnet-blockexplorer.electroneum.com/address/0x50bc20b7df9e564f7A86e7C4Bce5Ab4C8bDA04BD)
- **SellerPadiShipment Proxy:** [`0x44586E2f2761105f1e7a3e65E9bFd8295Ce536aD`](https://testnet-blockexplorer.electroneum.com/address/0x44586E2f2761105f1e7a3e65E9bFd8295Ce536aD)
- **SellerPadiShipment Implementation:** [`0x20c795DF5B0815a46c5B7230B350edFA4cBA5D5b`](https://testnet-blockexplorer.electroneum.com/address/0x20c795DF5B0815a46c5B7230B350edFA4cBA5D5b)

### Electroneum Mainnet (Chain ID `52014`)

- **Block Explorer:** [https://blockexplorer.electroneum.com](https://blockexplorer.electroneum.com)
- **Backend Signer Witness:** [`0x2755f9B4FE69D78C51271e81e03c1F865e92C045`](https://blockexplorer.electroneum.com/address/0x2755f9B4FE69D78C51271e81e03c1F865e92C045)
- **SellerPadiReceipt Proxy:** [`0x44E0A4020eD2bf00C99047A449775c68a9E0C578`](https://blockexplorer.electroneum.com/address/0x44E0A4020eD2bf00C99047A449775c68a9E0C578)
- **SellerPadiReceipt Implementation:** [`0xA8E042374a2b2f5f06CC87455dAEfD614978d526`](https://blockexplorer.electroneum.com/address/0xA8E042374a2b2f5f06CC87455dAEfD614978d526)
- **SellerPadiShipment Proxy:** [`0x040BEc94Dd3Cb4C9D42c6b7896D32aEb3E3C89F5`](https://blockexplorer.electroneum.com/address/0x040BEc94Dd3Cb4C9D42c6b7896D32aEb3E3C89F5)
- **SellerPadiShipment Implementation:** [`0xE25b39D09CA340a966a89f71E91BAC974c400f55`](https://blockexplorer.electroneum.com/address/0xE25b39D09CA340a966a89f71E91BAC974c400f55)

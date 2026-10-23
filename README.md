# SellerPadi Smart Contracts — Avalanche C-Chain

**SellerPadi** is a paperless merchant operating system and trust protocol built for retailers, SMEs, and commercial dispatchers. These smart contracts anchor tamper-proof digital sales receipts, audit trails, and logistics package handover verifications onto **Avalanche C-Chain**, harnessing sub-second transaction finality and minimal gas costs for real-time counter checkouts.

---

## Architecture Overview

SellerPadi's on-chain architecture utilizes the **ERC-1967 UUPS (Universal Upgradeable Proxy Standard)** pattern with backend cryptographic signer witness verification:

1. **`SellerPadiReceipt.sol`**:
   - Anchors SHA-256 hashes of digital sales receipts.
   - Enforces audit-safe voiding controls (only the issuing merchant/cashier can void a receipt with a mandatory reason string).
   - Manages store credit settlement records on-chain.
   - Gasless customer and merchant experience: uses backend EIP-712 / message hash signatures with nonce tracking to prevent replay attacks.

2. **`SellerPadiShipment.sol`**:
   - Manages the lifecycle of tracked package dispatches (`Created` → `InTransit` → `Delivered` → `Verified` / `Disputed`).
   - Integrates dual-layer physical QR labels with scratch-off inner PIN verifications (`RSIT-XXXX`).
   - Enforces cryptographic proof of physical custody transfer upon customer handover.

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

### 1. Avalanche Fuji Testnet (Chain ID `43113`)

Deploy implementation and UUPS proxy contracts to Avalanche Fuji:

```shell
# Deploy SellerPadiReceipt (Implementation + Proxy)
forge script scripts/SellerPadiReceipt.s.sol:SellerPadiReceiptScript \
  --rpc-url avalanche-fuji \
  --account deployer \
  --broadcast \
  --verify

# Deploy SellerPadiShipment (Implementation + Proxy)
forge script scripts/SellerPadiShipment.s.sol:SellerPadiShipmentScript \
  --rpc-url avalanche-fuji \
  --account deployer \
  --broadcast \
  --verify
```

### 2. Avalanche Mainnet (Chain ID `43114`)

Deploy to Avalanche C-Chain Mainnet:

```shell
forge script scripts/SellerPadiReceipt.s.sol:SellerPadiReceiptScript \
  --rpc-url avalanche \
  --account myWallet \
  --broadcast \
  --verify

forge script scripts/SellerPadiShipment.s.sol:SellerPadiShipmentScript \
  --rpc-url avalanche \
  --account myWallet \
  --broadcast \
  --verify
```

---

## Deployed Contract Addresses

### Avalanche Fuji Testnet (Chain ID `43113`)

- **SellerPadiReceipt Proxy:** [`0x910Ba81487FE94E97A30EF72B139a3237b579ea5`](https://testnet.snowtrace.io/address/0x910Ba81487FE94E97A30EF72B139a3237b579ea5)
- **SellerPadiReceipt Implementation:** [`0x234c7c29B22bdB16E16A8C3eB75514622094e1f4`](https://testnet.snowtrace.io/address/0x234c7c29B22bdB16E16A8C3eB75514622094e1f4)
- **SellerPadiShipment Proxy:** [`0x32Fd4b31c23f3C3ff168Eb308F53723F9B672381`](https://testnet.snowtrace.io/address/0x32Fd4b31c23f3C3ff168Eb308F53723F9B672381)
- **SellerPadiShipment Implementation:** [`0x9320D21c284288452fA75b70636543108e5a3986`](https://testnet.snowtrace.io/address/0x9320D21c284288452fA75b70636543108e5a3986)

### Avalanche C-Chain Mainnet (Chain ID `43114`)

- **SellerPadiReceipt Proxy:** `TBD`
- **SellerPadiReceipt Implementation:** `TBD`
- **SellerPadiShipment Proxy:** `TBD`
- **SellerPadiShipment Implementation:** `TBD`

---

## Security & Access Control

- **UUPS Upgradeability**: Both contracts inherit from `@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol` with strict `onlyOwner` access checks on `_authorizeUpgrade`.
- **EIP-712 & Nonce Replay Protection**: State updates signed by the backend relayer require strict sequential user nonces (`userNonces[sender]`) and deadline checks.
- **Zero PII On-Chain**: No customer names, phone numbers, or inventory line items touch the blockchain. Only cryptographic SHA-256 hashes (`receiptHash`, `innerSecretHash`) are stored on-chain.

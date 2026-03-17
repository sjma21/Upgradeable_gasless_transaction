# Gasless Vault

A UUPS-upgradeable ERC-20 token vault on OP Sepolia that supports **gasless transactions** via ERC-2771 meta-transactions. Users sign typed data off-chain; a trusted relayer submits the transaction on-chain and pays the gas.

---

## Architecture

```
User (signs EIP-712 message)
        │
        ▼
   sign.js  ──► request.json
        │
        ▼
  relayer.js
        │
        ▼
ERC2771Forwarder  ──► GaslessVault Proxy (ERC1967)
                              │
                              ▼
                    GaslessVault Implementation
```

### Contracts

| Contract | Description |
|---|---|
| `GaslessVault` | Core vault logic — deposit, withdraw, mint, burn, UUPS upgrade |
| `ERC1967Proxy` | Transparent proxy pointing to the GaslessVault implementation |
| `ERC2771Forwarder` | OZ v5 forwarder that verifies EIP-712 signatures and relays calls |
| `TestToken` | Simple ERC-20 token (1000 TT minted to deployer) used for testing |

### Deployed Contracts — OP Sepolia

| Contract | Address |
|---|---|
| ERC2771Forwarder | `0x3934B1836332B302e0De445C3111290d2c8D4C68` |
| TestToken | `0x0b6975D82891c01183E446a762023Ef73006D481` |
| GaslessVault (Implementation) | `0x6caCcA4016e84d0AD02965Cf35807420E67b175A` |
| GaslessVault (Proxy) | `0xe90766e5a0564680b3470EF43B4500EEF7CC6bd7` |

---

## How It Works

1. **User signs** a `ForwardRequest` off-chain using EIP-712 typed data (via `sign.js`). The request encodes which vault function to call, a nonce, and a deadline.
2. The signed request is saved to `relayer/request.json`.
3. **Relayer submits** the request to `ERC2771Forwarder.execute()` (via `relayer.js`), paying the gas.
4. The forwarder verifies the signature, increments the user's nonce (replay protection), and calls the vault proxy with the original user's address appended to `msg.data`.
5. The vault reads `_msgSender()` via `ERC2771Context`, which recovers the original signer — not the relayer — so access control and balance accounting work correctly.

---

## Project Structure

```
gasless-vault/
├── src/
│   ├── GaslessVault.sol       # Vault implementation
│   └── TestToken.sol          # ERC-20 test token
├── script/
│   └── Deploy.s.sol           # Forge deploy script
├── test/
│   └── GaslessVault.t.sol     # Forge test suite (29 tests)
├── relayer/
│   ├── sign.js                # Signs a meta-transaction and writes request.json
│   ├── relayer.js             # Reads request.json and submits to the forwarder
│   └── request.json           # Generated signed request (gitignored in prod)
├── remappings.txt             # Foundry import remappings
└── foundry.toml               # Foundry configuration
```

---

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js >= 18
- An OP Sepolia RPC URL (public: `https://sepolia.optimism.io`)

---

## Setup

```shell
# Install Foundry dependencies
forge install

# Install Node dependencies for the relayer
cd relayer && npm install && cd ..
```

---

## Build

```shell
forge build
```

---

## Test

```shell
# Run all tests
forge test --match-path test/GaslessVault.t.sol -v

# Run with coverage report
forge coverage --match-path test/GaslessVault.t.sol --report summary
```

**Coverage — GaslessVault.sol**

| Metric | Coverage |
|---|---|
| Lines | 90.91% |
| Statements | 86.67% |
| Branches | 100% |
| Functions | 88.89% |

---

## Deploy

```shell
forge script script/Deploy.s.sol:Deploy \
  --rpc-url https://sepolia.optimism.io \
  --private-key <DEPLOYER_PRIVATE_KEY> \
  --broadcast \
  --verify
```

The script deploys in order:
1. `ERC2771Forwarder("GaslessForwarder")`
2. `TestToken`
3. `GaslessVault` implementation (constructor receives forwarder address)
4. `ERC1967Proxy` (calls `initialize(token, deployer)`)

After deployment, update `FORWARDER_ADDRESS` and `VAULT_ADDRESS` in both `relayer/sign.js` and `relayer/relayer.js`.

---

## Sending a Gasless Transaction

### Step 1 — User signs a request

Edit `relayer/sign.js` to set the function you want to call (e.g. `deposit`, `withdraw`, `mint`, `burn`), then run:

```shell
cd relayer
node sign.js
# writes request.json
```

Key parameters in `sign.js`:

| Parameter | Description |
|---|---|
| `USER_PRIVATE_KEY` | Signer's private key. Use the **owner** key for `mint`. |
| `FORWARDER_ADDRESS` | Deployed `ERC2771Forwarder` address |
| `VAULT_ADDRESS` | Deployed proxy address |

### Step 2 — Relayer submits the request

```shell
node relayer.js
# prints tx hash and waits for confirmation
```

The relayer pays all gas. The vault sees the original user as `msg.sender` via `_msgSender()`.

---

## Vault Functions

| Function | Access | Description |
|---|---|---|
| `deposit(uint256 amount)` | Any user | Transfers tokens from user to vault; credits internal balance |
| `withdraw(uint256 amount)` | Any user | Burns internal balance and sends tokens back to user |
| `mint(address user, uint256 amount)` | Owner only | Credits internal balance without token transfer |
| `burn(uint256 amount)` | Any user | Destroys internal balance without returning tokens |
| `upgradeToAndCall(address, bytes)` | Owner only | UUPS upgrade entrypoint |

> **Note:** `deposit` requires the user to have approved the vault proxy for the token amount before calling. This approval must be a regular gas-paying transaction.

---

## Local Development with Anvil

```shell
# Start local node
anvil

# Deploy locally
forge script script/Deploy.s.sol:Deploy \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <ANVIL_PRIVATE_KEY> \
  --broadcast
```

Update `RPC_URL`, `FORWARDER_ADDRESS`, and `VAULT_ADDRESS` in the relayer scripts after each local deploy — Anvil resets state on restart.

---

## Security Notes

- **Never commit private keys.** Move keys to a `.env` file and use `dotenv` in the relayer scripts.
- The trusted forwarder is set as an **immutable** in the implementation constructor — it cannot be changed after deployment.
- Replay attacks are prevented by the forwarder's per-address nonce tracking.
- Only the owner can call `mint` and `upgradeToAndCall`, even through gasless meta-transactions.

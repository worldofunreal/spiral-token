# Spiral Token - Cross-Chain Token

Cross-chain ERC20/SPL token that exists on Ethereum, Solana, and other EVM chains with synchronized supply using LayerZero.

## Features

- ✅ Cross-chain transfers between Ethereum, Solana, and other EVM chains
- ✅ Synchronized total supply across all chains
- ✅ Secure nonce-based replay attack prevention
- ✅ Pausable functionality
- ✅ Maximum supply cap (1 billion tokens)
- ✅ Comprehensive test coverage (25 Foundry tests)

## Quick Start

### Prerequisites

- **Foundry** - For building and testing Solidity contracts
  ```bash
  curl -L https://foundry.paradigm.xyz | bash
  foundryup
  ```
- **Node.js** 18+ - For deployment scripts (optional, only if using Hardhat deployment)
- **Anchor** - For Solana program (only if deploying to Solana)
  ```bash
  cargo install --git https://github.com/coral-xyz/anchor avm --locked --force
  avm install latest && avm use latest
  ```

### Install Dependencies

```bash
# Install Node.js dependencies (for deployment scripts only)
npm install

# Install Foundry dependencies (forge-std)
forge install foundry-rs/forge-std --no-commit
```

## Build & Test

### Build Contracts (Foundry)

```bash
# Build Solidity contracts
forge build

# Build with verbose output
forge build -vvv
```

### Test Contracts (Foundry)

```bash
# Run all tests
forge test

# Run with verbose output
forge test -vvv

# Run specific test
forge test --match-test test_CrossChainTransfer

# Run with gas reporting
forge test --gas-report
```

### Build Solana Program

```bash
cd solana
anchor build
cd ..
```

## Deployment

**Note:** Hardhat is only needed for deployment scripts. If you prefer, you can use Foundry Scripts instead.

### Option 1: Using Hardhat (Current)

1. **Set up `.env` file:**
```bash
PRIVATE_KEY=0xYourPrivateKey
SOLANA_PRIVATE_KEY=YourBase58Key
```

2. **Deploy to EVM chains:**
```bash
npx hardhat run scripts/deploy-evm.js --network mainnet
npx hardhat run scripts/deploy-evm.js --network polygon
# ... etc
```

3. **Deploy to Solana:**
```bash
SOLANA_NETWORK=mainnet node scripts/deploy-solana.js
```

4. **Set trusted remotes:**
```bash
npx hardhat run scripts/set-trusted-remote.js --network mainnet
```

### Option 2: Using Foundry Scripts (Recommended)

You can create Foundry scripts for deployment. See `scripts/` directory for examples.

## Project Structure

```
├── ethereum/
│   └── SpiralToken.sol          # Main ERC20 contract
├── solana/
│   └── programs/
│       └── spiral-token/        # Solana program
├── scripts/
│   ├── deploy-evm.js            # Deploy to EVM chains (Hardhat)
│   ├── deploy-solana.js         # Deploy to Solana
│   └── set-trusted-remote.js    # Configure cross-chain (Hardhat)
├── test/
│   └── foundry/                 # Foundry tests
├── foundry.toml                 # Foundry configuration
└── hardhat.config.js            # Hardhat config (deployment only)
```

## Supported Chains

- Ethereum (Mainnet, Sepolia)
- Polygon (Mainnet, Mumbai)
- Arbitrum (Mainnet, Sepolia)
- BSC (Mainnet, Testnet)
- Avalanche (Mainnet, Fuji)
- Optimism (Mainnet, Sepolia)
- Base (Mainnet, Sepolia)
- Solana (Mainnet, Devnet)

## Development Workflow

### 1. Build
```bash
forge build
```

### 2. Test
```bash
forge test -vvv
```

### 3. Deploy (if needed)
```bash
# Using Hardhat
npx hardhat run scripts/deploy-evm.js --network sepolia
```

## Do I Need Hardhat?

**Short answer:** Only if you want to use the existing deployment scripts.

**For building and testing:** No, use Foundry:
- `forge build` - Compile contracts
- `forge test` - Run tests

**For deployment:** You have two options:
1. Keep Hardhat (current setup) - Scripts are already written
2. Use Foundry Scripts - Rewrite deployment scripts using Foundry

If you only care about building and testing, you can remove Hardhat entirely and just use Foundry.

## Documentation

- **[DEPLOYMENT.md](./DEPLOYMENT.md)** - Complete deployment guide for all networks
- **[OPERATIONS.md](./OPERATIONS.md)** - Operational runbook for monitoring and maintenance
- **[SECURITY.md](./SECURITY.md)** - Security documentation and threat model
- **[docs/INTEGRATION.md](./docs/INTEGRATION.md)** - Integration guide for dApps
- **[docs/SOLANA_INTEGRATION.md](./docs/SOLANA_INTEGRATION.md)** - Solana LayerZero integration details

## License

MIT

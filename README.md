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

### Install Dependencies

```bash
npm install
```

### Build

```bash
# Compile Solidity contracts
npm run compile

# Build Solana program
cd solana && anchor build && cd ..
```

### Test

```bash
npm test
```

## Deployment

See [DEPLOY.md](./DEPLOY.md) for complete deployment instructions.

### Quick Deploy

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

## Project Structure

```
├── ethereum/
│   └── SpiralToken.sol          # Main ERC20 contract
├── solana/
│   └── programs/
│       └── spiral-token/        # Solana program
├── scripts/
│   ├── deploy-evm.js            # Deploy to EVM chains
│   ├── deploy-solana.js         # Deploy to Solana
│   └── set-trusted-remote.js    # Configure cross-chain
├── test/
│   └── foundry/                 # Foundry tests
└── DEPLOY.md                    # Deployment guide
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

## License

MIT

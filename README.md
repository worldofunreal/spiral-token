# Cross-Chain Spiral Token

A cross-chain token implementation that exists on both Ethereum and Solana with synchronized distribution using LayerZero for cross-chain messaging.

## Architecture

### Ethereum (Sepolia)
- ERC20 token with LayerZero integration
- Cross-chain transfer capabilities
- Total supply: 1 billion tokens
- Initial supply: 1 million tokens

### Solana (Devnet)
- SPL token using Anchor framework
- Cross-chain messaging integration
- Same total supply and distribution as Ethereum

## Features

- **Cross-chain transfers**: Move tokens between Ethereum and Solana
- **Synchronized supply**: Total supply maintained across both chains
- **Security**: Nonce-based replay attack prevention
- **Decentralized**: No single point of failure

## Setup

### Prerequisites
- Node.js 16+
- Solana CLI
- Anchor framework
- Hardhat

### Installation

```bash
# Install dependencies
npm install

# Install Solana/Anchor dependencies
npm install -g @solana/cli
npm install -g @project-serum/anchor
```

### Environment Variables

Create a `.env` file:
```
PRIVATE_KEY=your_ethereum_private_key
INFURA_API_KEY=your_infura_api_key
ETHEREUM_RPC_URL=https://sepolia.infura.io/v3/YOUR_API_KEY
ETHERSCAN_API_KEY=your_etherscan_api_key
```

## Deployment

### Ethereum Deployment
```bash
npm run compile
npm run deploy:ethereum
```

### Solana Deployment
```bash
cd solana
anchor build
npm run deploy:solana
```

## Cross-Chain Configuration

After deploying both chains, you need to configure the trusted remote addresses:

### Ethereum
```javascript
// Set Solana as trusted remote
await spiralToken.setTrustedRemote(
  SOLANA_CHAIN_ID,
  solanaProgramId
);
```

### Solana
```javascript
// Set Ethereum contract as trusted remote
await program.methods
  .setTrustedRemote(ETHEREUM_CHAIN_ID, ethereumContractAddress)
  .rpc();
```

## Usage

### Cross-Chain Transfer (Ethereum → Solana)
```javascript
await spiralToken.crossChainTransfer(
  SOLANA_CHAIN_ID,
  solanaRecipientAddress,
  amount,
  zroPaymentAddress,
  adapterParams
);
```

### Cross-Chain Transfer (Solana → Ethereum)
```javascript
await program.methods
  .crossChainTransfer(
    ETHEREUM_CHAIN_ID,
    ethereumRecipientAddress,
    amount,
    nonce
  )
  .accounts({
    // Account mappings
  })
  .rpc();
```

## Testing

```bash
# Ethereum tests
npm test

# Solana tests
cd solana && anchor test
```

## Security Considerations

- All cross-chain transfers use unique nonces to prevent replay attacks
- Trusted remote addresses must be configured for security
- Total supply is enforced on both chains
- Bridge contracts are upgradeable with proper governance

## Token Details

- **Name**: Spiral Token
- **Symbol**: SPIRAL
- **Decimals**: 8
- **Max Supply**: 1,000,000,000 tokens
- **Initial Supply**: 1,000,000 tokens

## Networks

- **Ethereum**: Sepolia Testnet
- **Solana**: Devnet

## Future Enhancements

- Mainnet deployment
- Additional chain support (BSC, Polygon, etc.)
- Governance mechanism
- Liquidity pools integration
- Staking functionality
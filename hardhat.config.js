import "@nomicfoundation/hardhat-ethers";
import "@nomicfoundation/hardhat-verify";
import "dotenv/config";

const PRIVATE_KEY = process.env.PRIVATE_KEY || "0x" + "0".repeat(64);
const INFURA_API_KEY = process.env.INFURA_API_KEY || "";
const ETHEREUM_RPC_URL = process.env.ETHEREUM_RPC_URL || `https://sepolia.infura.io/v3/${INFURA_API_KEY}`;

export default {
  paths: {
    sources: "./ethereum",
  },
  solidity: {
    version: "0.8.30",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    sepolia: {
      type: "http",
      url: ETHEREUM_RPC_URL,
      accounts: [PRIVATE_KEY],
      chainId: 11155111
    },
    mainnet: {
      type: "http",
      url: process.env.ETHEREUM_RPC_URL || `https://mainnet.infura.io/v3/${INFURA_API_KEY}`,
      accounts: [PRIVATE_KEY],
      chainId: 1
    }
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY
  }
};

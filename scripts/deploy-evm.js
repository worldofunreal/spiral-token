import hre from "hardhat";
import fs from "fs";

// LayerZero Endpoint Addresses
// Source: https://layerzero.gitbook.io/docs/technical-reference/mainnet/supported-chain-ids
const LZ_ENDPOINTS = {
  // Mainnets
  1: "0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675",      // Ethereum
  137: "0x3c2269811836af69497E5F486A85D7316753cf62",   // Polygon
  42161: "0x3c2269811836af69497E5F486A85D7316753cf62", // Arbitrum
  56: "0x3c2269811836af69497E5F486A85D7316753cf62",    // BSC
  43114: "0x3c2269811836af69497E5F486A85D7316753cf62", // Avalanche
  10: "0x3c2269811836af69497E5F486A85D7316753cf62",    // Optimism
  8453: "0xb6319cC6c8c27A8F5dAF0dD3DF91EA35C4720dd7",  // Base
  
  // Testnets
  11155111: "0x6FED9a431d6478273E724418b936B3b7943844A1", // Sepolia
  80001: "0xf69186dfBa60DdB133E91E9A4B5673624293d8F8",    // Mumbai
  421614: "0x6aB5Ae682b7042b28C08B2952A28eF7C8b6Dac9c",    // Arbitrum Sepolia
  97: "0x6Fcb97553D41516Cb228ac03FdC8B9a0a9df04A1",      // BSC Testnet
  43113: "0x93f54D755A063cE7bB9e6AcCFE8882F060B2a57C",     // Fuji
  11155420: "0x3c2269811836af69497E5F486A85D7316753cf62", // Optimism Sepolia
  84532: "0x6aB5Ae682b7042b28C08B2952A28eF7C8b6Dac9c"     // Base Sepolia
};

const NETWORK_NAMES = {
  1: "ethereum",
  137: "polygon",
  42161: "arbitrum",
  56: "bsc",
  43114: "avalanche",
  10: "optimism",
  8453: "base",
  11155111: "sepolia",
  80001: "mumbai",
  421614: "arbitrumSepolia",
  97: "bscTestnet",
  43113: "fuji",
  11155420: "optimismSepolia",
  84532: "baseSepolia"
};

async function main() {
  const network = await hre.ethers.provider.getNetwork();
  const chainId = Number(network.chainId);
  const networkName = NETWORK_NAMES[chainId] || `chain-${chainId}`;
  
  console.log(`\n🚀 Deploying SpiralToken to ${networkName} (Chain ID: ${chainId})...\n`);
  
  const lzEndpoint = LZ_ENDPOINTS[chainId];
  if (!lzEndpoint) {
    throw new Error(`❌ No LayerZero endpoint found for chain ID ${chainId}`);
  }
  
  const [deployer] = await hre.ethers.getSigners();
  const balance = await hre.ethers.provider.getBalance(deployer.address);
  
  console.log(`📝 Deployer: ${deployer.address}`);
  console.log(`💰 Balance: ${hre.ethers.formatEther(balance)} ${networkName === "bsc" || networkName === "bscTestnet" ? "BNB" : "ETH"}`);
  console.log(`🔗 LayerZero Endpoint: ${lzEndpoint}\n`);
  
  if (balance < hre.ethers.parseEther("0.01")) {
    throw new Error("❌ Insufficient balance for deployment");
  }
  
  // Token parameters
  const name = "Spiral Token";
  const symbol = "SPIRAL";
  const initialSupply = 1000000; // 1 million tokens (will be multiplied by 10^18 in constructor)
  
  console.log("📦 Deploying contract...");
  const SpiralToken = await hre.ethers.getContractFactory("SpiralToken");
  const spiralToken = await SpiralToken.deploy(
    lzEndpoint,
    name,
    symbol,
    initialSupply
  );
  
  await spiralToken.waitForDeployment();
  const address = await spiralToken.getAddress();
  
  console.log(`\n✅ SpiralToken deployed to: ${address}\n`);
  
  // Save deployment info
  const deployments = JSON.parse(fs.readFileSync("./deployments.json", "utf8") || "{}");
  deployments[networkName] = {
    address,
    chainId: chainId.toString(),
    lzEndpoint,
    name,
    symbol,
    initialSupply,
    deployer: deployer.address,
    timestamp: new Date().toISOString()
  };
  fs.writeFileSync("./deployments.json", JSON.stringify(deployments, null, 2));
  
  console.log(`💾 Deployment info saved to deployments.json`);
  console.log(`\n📋 Next steps:`);
  console.log(`   1. Verify contract: npx hardhat verify --network ${networkName} ${address} ${lzEndpoint} "${name}" "${symbol}" ${initialSupply}`);
  console.log(`   2. Set trusted remotes after deploying to other chains`);
  console.log(`   3. Check deployments.json for all contract addresses\n`);
  
  return { address, spiralToken };
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });



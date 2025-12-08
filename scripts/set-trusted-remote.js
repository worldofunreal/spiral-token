import hre from "hardhat";
import fs from "fs";

// LayerZero Chain IDs
const LZ_CHAIN_IDS = {
  ethereum: 101,
  polygon: 109,
  arbitrum: 110,
  bsc: 102,
  avalanche: 106,
  optimism: 111,
  base: 184,
  solana: 102 // Check latest docs
};

async function main() {
  const deployments = JSON.parse(fs.readFileSync("./deployments.json", "utf8") || "{}");
  
  if (Object.keys(deployments).length < 2) {
    throw new Error("❌ Need at least 2 deployments to set trusted remotes");
  }
  
  console.log("\n🔗 Setting up trusted remotes...\n");
  
  // Get network info
  const network = await hre.ethers.provider.getNetwork();
  const chainId = Number(network.chainId);
  
  // Find current deployment
  const currentDeployment = Object.entries(deployments).find(
    ([_, info]) => info.chainId === chainId.toString()
  );
  
  if (!currentDeployment) {
    throw new Error(`❌ No deployment found for chain ID ${chainId}`);
  }
  
  const [currentNetwork, currentInfo] = currentDeployment;
  const currentContract = await hre.ethers.getContractAt("SpiralToken", currentInfo.address);
  const [deployer] = await hre.ethers.getSigners();
  
  console.log(`📝 Current network: ${currentNetwork}`);
  console.log(`📝 Contract: ${currentInfo.address}\n`);
  
  // Set trusted remotes for all other deployments
  for (const [networkName, info] of Object.entries(deployments)) {
    if (networkName === currentNetwork) continue;
    
    let remoteChainId;
    let remoteAddress;
    
    if (networkName.startsWith('solana-')) {
      // Solana uses program ID as bytes32
      remoteChainId = LZ_CHAIN_IDS.solana;
      // Convert Solana public key to bytes32 format
      const solanaPubkey = new hre.ethers.AbiCoder().encode(
        ["bytes32"],
        [hre.ethers.zeroPadValue(info.programId, 32)]
      );
      remoteAddress = solanaPubkey;
    } else {
      // EVM chains
      remoteChainId = LZ_CHAIN_IDS[networkName] || parseInt(info.chainId);
      // Pack address as bytes
      remoteAddress = hre.ethers.solidityPacked(["address"], [info.address]);
    }
    
    console.log(`🔗 Setting trusted remote: ${networkName} (Chain ID: ${remoteChainId})`);
    console.log(`   Remote address: ${info.address || info.programId}`);
    
    try {
      const tx = await currentContract.setTrustedRemote(remoteChainId, remoteAddress);
      await tx.wait();
      console.log(`   ✅ Transaction: ${tx.hash}\n`);
    } catch (error) {
      console.log(`   ⚠️  Error: ${error.message}\n`);
    }
  }
  
  console.log("✅ Trusted remotes configured!\n");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });



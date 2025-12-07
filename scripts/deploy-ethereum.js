const { ethers } = require("hardhat");
const fs = require("fs");

async function deployEthereum() {
  console.log("Deploying Spiral Token to Ethereum...");
  
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Account balance:", (await deployer.getBalance()).toString());

  // LayerZero endpoint for Sepolia testnet
  const lzEndpointAddress = "0x6FED9a431d6478273E724418b936B3b7943844A1";
  
  // Token parameters
  const name = "Spiral Token";
  const symbol = "SPIRAL";
  const initialSupply = 1000000; // 1 million tokens

  const SpiralToken = await ethers.getContractFactory("SpiralToken");
  const spiralToken = await SpiralToken.deploy(
    lzEndpointAddress,
    name,
    symbol,
    initialSupply
  );

  await spiralToken.deployed();
  console.log("SpiralToken deployed to:", spiralToken.address);

  // Save deployment info
  const deploymentInfo = {
    contractAddress: spiralToken.address,
    network: "sepolia",
    chainId: 11155111,
    deployer: deployer.address,
    lzEndpoint: lzEndpointAddress,
    initialSupply: initialSupply,
    timestamp: new Date().toISOString()
  };

  fs.writeFileSync(
    "./ethereum-deployment.json",
    JSON.stringify(deploymentInfo, null, 2)
  );

  console.log("Deployment info saved to ethereum-deployment.json");
  
  // Set up trusted remote for Solana (will be updated after Solana deployment)
  console.log("Note: You'll need to set up trusted remote addresses after Solana deployment");
  
  return spiralToken;
}

deployEthereum()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
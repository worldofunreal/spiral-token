import { Connection, Keypair, PublicKey, SystemProgram, LAMPORTS_PER_SOL } from '@solana/web3.js';
import { TOKEN_PROGRAM_ID, createMint, createAssociatedTokenAccount, mintTo } from '@solana/spl-token';
import * as anchor from '@coral-xyz/anchor';
import fs from 'fs';
import bs58 from 'bs58';

// Load private key from environment
function getKeypairFromPrivateKey() {
  const privateKey = process.env.SOLANA_PRIVATE_KEY;
  if (!privateKey) {
    throw new Error("❌ SOLANA_PRIVATE_KEY not found in environment variables");
  }
  
  // Handle both base58 and hex formats
  let secretKey;
  if (privateKey.startsWith('[')) {
    // Array format
    secretKey = JSON.parse(privateKey);
  } else if (privateKey.startsWith('0x')) {
    // Hex format
    secretKey = Array.from(Buffer.from(privateKey.slice(2), 'hex'));
  } else {
    // Base58 format
    secretKey = Array.from(bs58.decode(privateKey));
  }
  
  return Keypair.fromSecretKey(new Uint8Array(secretKey));
}

async function deploySolana() {
  const network = process.env.SOLANA_NETWORK || 'devnet';
  const rpcUrl = network === 'mainnet' 
    ? process.env.SOLANA_MAINNET_RPC_URL || 'https://api.mainnet-beta.solana.com'
    : process.env.SOLANA_DEVNET_RPC_URL || 'https://api.devnet.solana.com';
  
  console.log(`\n🚀 Deploying Spiral Token to Solana ${network}...\n`);
  
  const connection = new Connection(rpcUrl, 'confirmed');
  const wallet = getKeypairFromPrivateKey();
  
  console.log(`📝 Deployer wallet: ${wallet.publicKey.toString()}`);
  
  const balance = await connection.getBalance(wallet.publicKey);
  console.log(`💰 Balance: ${balance / LAMPORTS_PER_SOL} SOL\n`);
  
  if (network === 'devnet' && balance < 2 * LAMPORTS_PER_SOL) {
    console.log("💧 Requesting airdrop...");
    const airdrop = await connection.requestAirdrop(wallet.publicKey, 2 * LAMPORTS_PER_SOL);
    await connection.confirmTransaction(airdrop);
    console.log("✅ Airdrop received\n");
  } else if (network === 'mainnet' && balance < 0.1 * LAMPORTS_PER_SOL) {
    throw new Error("❌ Insufficient SOL balance for mainnet deployment");
  }
  
  // Load Anchor program
  const programIdPath = './solana/target/deploy/spiral_token-keypair.json';
  if (!fs.existsSync(programIdPath)) {
    throw new Error(`❌ Program keypair not found at ${programIdPath}. Run 'cd solana && anchor build' first.`);
  }
  
  const programKeypair = Keypair.fromSecretKey(
    new Uint8Array(JSON.parse(fs.readFileSync(programIdPath, 'utf8')))
  );
  const programId = programKeypair.publicKey;
  
  console.log(`📦 Program ID: ${programId.toString()}\n`);
  
  // Check if program is already deployed
  const programInfo = await connection.getAccountInfo(programId);
  if (!programInfo) {
    console.log("⚠️  Program not deployed. Deploy it first with:");
    console.log(`   cd solana && anchor deploy --provider.cluster ${network}\n`);
    throw new Error("Program not deployed");
  }
  
  const provider = new anchor.AnchorProvider(
    connection,
    new anchor.Wallet(wallet),
    { preflightCommitment: 'confirmed' }
  );
  
  // Load IDL
  const idlPath = './solana/target/idl/spiral_token.json';
  if (!fs.existsSync(idlPath)) {
    throw new Error(`❌ IDL not found at ${idlPath}. Run 'cd solana && anchor build' first.`);
  }
  
  const idl = JSON.parse(fs.readFileSync(idlPath, 'utf8'));
  const program = new anchor.Program(idl, programId, provider);
  
  // Token parameters
  const decimals = 8;
  const maxSupply = 1000000000 * Math.pow(10, decimals); // 1 billion tokens
  const initialSupply = 1000000 * Math.pow(10, decimals); // 1 million tokens
  
  console.log("📦 Creating SPL token mint...");
  const mint = await createMint(
    connection,
    wallet,
    wallet.publicKey,
    null,
    decimals
  );
  
  console.log(`✅ Mint created: ${mint.toString()}\n`);
  
  // Initialize mint data (if your program has this)
  const [mintDataPda] = PublicKey.findProgramAddressSync(
    [Buffer.from("mint_data"), mint.toBuffer()],
    program.programId
  );
  
  console.log(`📦 Initializing mint data at PDA: ${mintDataPda.toString()}`);
  try {
    await program.methods
      .initializeMint(new anchor.BN(decimals), new anchor.BN(maxSupply))
      .accounts({
        mint: mint,
        mintData: mintDataPda,
        authority: wallet.publicKey,
        tokenProgram: TOKEN_PROGRAM_ID,
        rent: SystemProgram.programId,
        systemProgram: SystemProgram.programId,
      })
      .rpc();
    console.log("✅ Mint data initialized\n");
  } catch (error) {
    if (error.message.includes("already in use")) {
      console.log("⚠️  Mint data already initialized\n");
    } else {
      throw error;
    }
  }
  
  // Create token account for deployer
  console.log("📦 Creating token account...");
  const tokenAccount = await createAssociatedTokenAccount(
    connection,
    wallet,
    mint,
    wallet.publicKey
  );
  console.log(`✅ Token account: ${tokenAccount.toString()}\n`);
  
  // Mint initial supply
  console.log(`📦 Minting initial supply: ${initialSupply / Math.pow(10, decimals)} tokens`);
  try {
    await program.methods
      .mintTokens(new anchor.BN(initialSupply))
      .accounts({
        mint: mint,
        mintData: mintDataPda,
        recipient: tokenAccount,
        authority: wallet.publicKey,
        tokenProgram: TOKEN_PROGRAM_ID,
      })
      .rpc();
    console.log("✅ Initial supply minted\n");
  } catch (error) {
    if (error.message.includes("already in use")) {
      console.log("⚠️  Initial supply already minted\n");
    } else {
      throw error;
    }
  }
  
  // Save deployment info
  const deployments = JSON.parse(fs.readFileSync("./deployments.json", "utf8") || "{}");
  deployments[`solana-${network}`] = {
    programId: programId.toString(),
    mint: mint.toString(),
    mintData: mintDataPda.toString(),
    tokenAccount: tokenAccount.toString(),
    network: network,
    decimals: decimals,
    maxSupply: maxSupply.toString(),
    initialSupply: initialSupply.toString(),
    deployer: wallet.publicKey.toString(),
    timestamp: new Date().toISOString()
  };
  fs.writeFileSync("./deployments.json", JSON.stringify(deployments, null, 2));
  
  console.log("💾 Deployment info saved to deployments.json");
  console.log(`\n✅ Solana deployment completed!`);
  console.log(`\n📋 Next steps:`);
  console.log(`   1. Set trusted remotes on all chains`);
  console.log(`   2. Configure LayerZero endpoints\n`);
  
  return {
    program,
    mint,
    mintDataPda,
    tokenAccount,
    wallet
  };
}

deploySolana()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ Deployment failed:", error.message);
    process.exit(1);
  });

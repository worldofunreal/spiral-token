const anchor = require('@project-serum/anchor');
const { Connection, PublicKey, Keypair, SystemProgram, LAMPORTS_PER_SOL } = require('@solana/web3.js');
const { TOKEN_PROGRAM_ID, createMint, createAssociatedTokenAccount, mintTo } = require('@solana/spl-token');
const fs = require('fs');

async function deploySolana() {
  console.log("Deploying Spiral Token to Solana...");
  
  // Configure the connection to devnet
  const connection = new Connection('https://api.devnet.solana.com', 'confirmed');
  const wallet = anchor.web3.Keypair.generate(); // Or load from file
  
  console.log("Deployer wallet:", wallet.publicKey.toString());
  
  // Airdrop SOL if needed
  const balance = await connection.getBalance(wallet.publicKey);
  if (balance < 2 * LAMPORTS_PER_SOL) {
    console.log("Requesting airdrop...");
    const airdrop = await connection.requestAirdrop(wallet.publicKey, 2 * LAMPORTS_PER_SOL);
    await connection.confirmTransaction(airdrop);
  }
  
  // Load the program
  const provider = new anchor.AnchorProvider(
    connection,
    new anchor.Wallet(wallet),
    { preflightCommitment: 'confirmed' }
  );
  
  const idl = JSON.parse(fs.readFileSync('./solana/target/idl/spiral_token.json', 'utf8'));
  const programId = new PublicKey(idl.metadata.address);
  const program = new anchor.Program(idl, programId, provider);
  
  // Create mint
  const mintKeypair = Keypair.generate();
  const decimals = 8;
  const maxSupply = 1000000000 * Math.pow(10, decimals); // 1 billion tokens
  
  console.log("Creating mint...");
  const mint = await createMint(
    connection,
    wallet,
    wallet.publicKey,
    null,
    decimals
  );
  
  console.log("Mint created:", mint.toString());
  
  // Initialize mint data
  const [mintDataPda] = await PublicKey.findProgramAddress(
    [Buffer.from("mint_data"), mint.toBuffer()],
    program.programId
  );
  
  console.log("Initializing mint data...");
  await program.methods
    .initializeMint(decimals, maxSupply)
    .accounts({
      mint: mint,
      mintData: mintDataPda,
      authority: wallet.publicKey,
      tokenProgram: TOKEN_PROGRAM_ID,
      rent: SystemProgram.programId,
      systemProgram: SystemProgram.programId,
    })
    .signers([wallet])
    .rpc();
  
  // Create token account for deployer
  const tokenAccount = await createAssociatedTokenAccount(
    connection,
    wallet,
    mint,
    wallet.publicKey
  );
  
  // Mint initial supply (1 million tokens)
  const initialSupply = 1000000 * Math.pow(10, decimals);
  await program.methods
    .mintTokens(initialSupply)
    .accounts({
      mint: mint,
      mintData: mintDataPda,
      recipient: tokenAccount,
      authority: wallet.publicKey,
      tokenProgram: TOKEN_PROGRAM_ID,
    })
    .signers([wallet])
    .rpc();
  
  console.log("Initial supply minted:", initialSupply);
  
  // Save deployment info
  const deploymentInfo = {
    programId: program.programId.toString(),
    mint: mint.toString(),
    mintData: mintDataPda.toString(),
    tokenAccount: tokenAccount.toString(),
    network: "devnet",
    decimals: decimals,
    maxSupply: maxSupply.toString(),
    initialSupply: initialSupply.toString(),
    deployer: wallet.publicKey.toString(),
    timestamp: new Date().toISOString()
  };
  
  fs.writeFileSync(
    "./solana-deployment.json",
    JSON.stringify(deploymentInfo, null, 2)
  );
  
  console.log("Deployment info saved to solana-deployment.json");
  console.log("Solana deployment completed!");
  
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
    console.error(error);
    process.exit(1);
  });
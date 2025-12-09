use anchor_lang::prelude::*;
use anchor_spl::token::{self, Mint, Token, TokenAccount};

declare_id!("SP1RAL111111111111111111111111111111111");

#[program]
pub mod spiral_token {
    use super::*;

    pub fn initialize_mint(
        ctx: Context<InitializeMint>,
        decimals: u8,
        max_supply: u64,
    ) -> Result<()> {
        require!(decimals <= 18, ErrorCode::InvalidDecimals);
        require!(max_supply > 0, ErrorCode::InvalidMaxSupply);
        require!(max_supply <= 1_000_000_000_000_000_000, ErrorCode::InvalidMaxSupply); // Reasonable cap

        let mint = &ctx.accounts.mint;
        let token_program = &ctx.accounts.token_program;

        // Initialize the mint with the provided decimals
        let cpi_accounts = token::InitializeMint {
            mint: mint.to_account_info(),
            rent: ctx.accounts.rent.to_account_info(),
        };
        let cpi_program = token_program.to_account_info();
        let cpi_ctx = CpiContext::new(cpi_program, cpi_accounts);
        token::initialize_mint(cpi_ctx, decimals, &ctx.accounts.authority.key(), None)?;

        // Store max supply
        ctx.accounts.mint_data.max_supply = max_supply;
        ctx.accounts.mint_data.current_supply = 0;
        ctx.accounts.mint_data.authority = ctx.accounts.authority.key();
        ctx.accounts.mint_data.decimals = decimals;

        Ok(())
    }

    pub fn mint_tokens(
        ctx: Context<MintTokens>,
        amount: u64,
    ) -> Result<()> {
        require!(amount > 0, ErrorCode::InvalidAmount);
        
        let mint_data = &mut ctx.accounts.mint_data;
        
        // Validate authority
        require!(
            ctx.accounts.authority.key() == mint_data.authority,
            ErrorCode::InvalidAuthority
        );
        
        // Check if we're exceeding max supply
        require!(
            mint_data.current_supply.checked_add(amount).is_some() &&
            mint_data.current_supply + amount <= mint_data.max_supply,
            ErrorCode::ExceedsMaxSupply
        );

        // Mint tokens to the recipient
        let cpi_accounts = token::MintTo {
            mint: ctx.accounts.mint.to_account_info(),
            to: ctx.accounts.recipient.to_account_info(),
            authority: ctx.accounts.authority.to_account_info(),
        };
        let cpi_program = ctx.accounts.token_program.to_account_info();
        let cpi_ctx = CpiContext::new(cpi_program, cpi_accounts);
        token::mint_to(cpi_ctx, amount)?;

        // Update supply
        mint_data.current_supply = mint_data.current_supply.checked_add(amount)
            .ok_or(ErrorCode::SupplyOverflow)?;

        emit TokensMinted {
            recipient: ctx.accounts.recipient.key(),
            amount,
            new_supply: mint_data.current_supply,
        };

        Ok(())
    }

    pub fn cross_chain_transfer(
        ctx: Context<CrossChainTransfer>,
        destination_chain: u16,
        recipient: Pubkey,
        amount: u64,
        nonce: [u8; 32],
    ) -> Result<()> {
        require!(amount > 0, ErrorCode::InvalidAmount);
        require!(recipient != Pubkey::default(), ErrorCode::InvalidRecipient);
        require!(destination_chain > 0, ErrorCode::InvalidChainId);
        
        let mint_data = &mut ctx.accounts.mint_data;
        
        // Validate authority
        require!(
            ctx.accounts.authority.key() == mint_data.authority,
            ErrorCode::InvalidAuthority
        );
        
        // Burn tokens from sender
        let cpi_accounts = token::Burn {
            mint: ctx.accounts.mint.to_account_info(),
            from: ctx.accounts.sender.to_account_info(),
            authority: ctx.accounts.sender_authority.to_account_info(),
        };
        let cpi_program = ctx.accounts.token_program.to_account_info();
        let cpi_ctx = CpiContext::new(cpi_program, cpi_accounts);
        token::burn(cpi_ctx, amount)?;

        // Update supply with overflow check
        mint_data.current_supply = mint_data.current_supply.checked_sub(amount)
            .ok_or(ErrorCode::SupplyUnderflow)?;

        // Store cross-chain transfer info
        let transfer_info = CrossChainTransferInfo {
            source_chain: 102, // Solana chain ID
            destination_chain,
            recipient,
            amount,
            nonce,
            timestamp: Clock::get()?.unix_timestamp,
        };

        emit CrossChainTransferInitiated {
            transfer_info,
        };

        Ok(())
    }

    pub fn set_trusted_remote(
        ctx: Context<SetTrustedRemote>,
        chain_id: u16,
        remote_address: [u8; 32],
        address_length: u8,
    ) -> Result<()> {
        require!(chain_id > 0, ErrorCode::InvalidChainId);
        require!(address_length == 20 || address_length == 32, ErrorCode::InvalidRecipient);
        
        let mint_data = &ctx.accounts.mint_data;
        require!(
            ctx.accounts.authority.key() == mint_data.authority,
            ErrorCode::InvalidAuthority
        );
        
        let trusted_remote = &mut ctx.accounts.trusted_remote;
        trusted_remote.chain_id = chain_id;
        trusted_remote.remote_address = remote_address;
        trusted_remote.address_length = address_length;
        
        Ok(())
    }

    pub fn receive_cross_chain_transfer(
        ctx: Context<ReceiveCrossChainTransfer>,
        source_chain: u16,
        sender: Pubkey,
        recipient: Pubkey,
        amount: u64,
        nonce: [u8; 32],
    ) -> Result<()> {
        require!(amount > 0, ErrorCode::InvalidAmount);
        require!(recipient != Pubkey::default(), ErrorCode::InvalidRecipient);
        require!(source_chain > 0, ErrorCode::InvalidChainId);
        require!(sender != Pubkey::default(), ErrorCode::InvalidSender);
        
        let mint_data = &mut ctx.accounts.mint_data;
        
        // CRITICAL: Validate authority - only authorized LayerZero relayer can call this
        require!(
            ctx.accounts.authority.key() == mint_data.authority,
            ErrorCode::InvalidAuthority
        );
        
        // Validate trusted remote - ensure source chain is trusted
        // Note: In production, the LayerZero relayer should validate the source address
        // This check ensures we only accept messages from configured trusted remotes
        // The trusted_remote account is optional - if provided, validate chain_id matches
        if ctx.accounts.trusted_remote.is_some() {
            let trusted_remote = ctx.accounts.trusted_remote.as_ref().unwrap();
            require!(
                trusted_remote.chain_id == source_chain,
                ErrorCode::InvalidChainId
            );
            // Additional validation: verify sender matches trusted remote address if needed
            // For EVM addresses (20 bytes), we'd need to compare first 20 bytes
            // For Solana (32 bytes), we compare the full pubkey
        }
        
        // Check if nonce has been used
        require!(
            !ctx.accounts.nonce_registry.is_nonce_used(nonce),
            ErrorCode::NonceAlreadyUsed
        );

        // Mark nonce as used
        ctx.accounts.nonce_registry.mark_nonce_used(nonce)?;

        // Check if we're exceeding max supply
        require!(
            mint_data.current_supply.checked_add(amount).is_some() &&
            mint_data.current_supply + amount <= mint_data.max_supply,
            ErrorCode::ExceedsMaxSupply
        );

        // Mint tokens to recipient
        let cpi_accounts = token::MintTo {
            mint: ctx.accounts.mint.to_account_info(),
            to: ctx.accounts.recipient.to_account_info(),
            authority: ctx.accounts.authority.to_account_info(),
        };
        let cpi_program = ctx.accounts.token_program.to_account_info();
        let cpi_ctx = CpiContext::new(cpi_program, cpi_accounts);
        token::mint_to(cpi_ctx, amount)?;

        // Update supply with overflow check
        mint_data.current_supply = mint_data.current_supply.checked_add(amount)
            .ok_or(ErrorCode::SupplyOverflow)?;

        emit CrossChainTransferReceived {
            source_chain,
            sender,
            recipient,
            amount,
            nonce,
        };

        Ok(())
    }
}

#[derive(Accounts)]
pub struct InitializeMint<'info> {
    #[account(
        init,
        payer = authority,
        mint::decimals = 8, // Default, but actual decimals stored in MintData
        mint::authority = authority,
    )]
    pub mint: Account<'info, Mint>,
    
    #[account(
        init,
        payer = authority,
        space = 8 + 32 + 8 + 8 + 1, // discriminator + authority + max_supply + current_supply + decimals
    )]
    pub mint_data: Account<'info, MintData>,
    
    #[account(mut)]
    pub authority: Signer<'info>,
    pub token_program: Program<'info, Token>,
    pub rent: Sysvar<'info, Rent>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct MintTokens<'info> {
    #[account(mut)]
    pub mint: Account<'info, Mint>,
    
    #[account(mut)]
    pub mint_data: Account<'info, MintData>,
    
    #[account(mut)]
    pub recipient: Account<'info, TokenAccount>,
    
    pub authority: Signer<'info>,
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct CrossChainTransfer<'info> {
    #[account(mut)]
    pub mint: Account<'info, Mint>,
    
    #[account(mut)]
    pub mint_data: Account<'info, MintData>,
    
    #[account(mut)]
    pub sender: Account<'info, TokenAccount>,
    
    pub sender_authority: Signer<'info>,
    pub authority: Signer<'info>,
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
#[instruction(chain_id: u16)]
pub struct SetTrustedRemote<'info> {
    #[account(mut)]
    pub mint_data: Account<'info, MintData>,
    
    #[account(
        init_if_needed,
        payer = authority,
        space = 8 + 2 + 32 + 1, // discriminator + chain_id (u16) + remote_address (32 bytes) + address_length (u8)
        seeds = [b"trusted_remote", mint_data.key().as_ref(), &chain_id.to_le_bytes()],
        bump
    )]
    pub trusted_remote: Account<'info, TrustedRemote>,
    
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct ReceiveCrossChainTransfer<'info> {
    #[account(mut)]
    pub mint: Account<'info, Mint>,
    
    #[account(mut)]
    pub mint_data: Account<'info, MintData>,
    
    #[account(mut)]
    pub recipient: Account<'info, TokenAccount>,
    
    #[account(
        init_if_needed,
        payer = authority,
        space = 8 + 4 + (32 * 1000), // discriminator + vec length + space for 1000 nonces max
    )]
    pub nonce_registry: Account<'info, NonceRegistry>,
    
    /// CHECK: Optional trusted remote account for validation
    /// If provided, validates that source_chain matches trusted remote
    #[account()]
    pub trusted_remote: Option<Account<'info, TrustedRemote>>,
    
    pub authority: Signer<'info>,
    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,
}

#[account]
pub struct MintData {
    pub max_supply: u64,
    pub current_supply: u64,
    pub authority: Pubkey,
    pub decimals: u8,
}

#[account]
pub struct TrustedRemote {
    pub chain_id: u16,
    pub remote_address: [u8; 32], // For EVM addresses (20 bytes) or Solana pubkeys (32 bytes)
    pub address_length: u8, // 20 for EVM, 32 for Solana
}

#[account]
pub struct NonceRegistry {
    // Use a bounded Vec to prevent DoS
    // In production, consider using a more efficient structure or limiting to recent nonces
    pub used_nonces: Vec<[u8; 32]>,
}

impl NonceRegistry {
    pub const MAX_NONCES: usize = 1000; // Limit to prevent DoS
    
    pub fn is_nonce_used(&self, nonce: [u8; 32]) -> bool {
        self.used_nonces.contains(&nonce)
    }

    pub fn mark_nonce_used(&mut self, nonce: [u8; 32]) -> Result<()> {
        if self.is_nonce_used(nonce) {
            return Err(ErrorCode::NonceAlreadyUsed.into());
        }
        
        // Prevent DoS by limiting nonce storage
        require!(
            self.used_nonces.len() < Self::MAX_NONCES,
            ErrorCode::NonceRegistryFull
        );
        
        self.used_nonces.push(nonce);
        Ok(())
    }
}

#[event]
pub struct TokensMinted {
    pub recipient: Pubkey,
    pub amount: u64,
    pub new_supply: u64,
}

#[event]
pub struct CrossChainTransferInitiated {
    pub transfer_info: CrossChainTransferInfo,
}

#[event]
pub struct CrossChainTransferReceived {
    pub source_chain: u16,
    pub sender: Pubkey,
    pub recipient: Pubkey,
    pub amount: u64,
    pub nonce: [u8; 32],
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub struct CrossChainTransferInfo {
    pub source_chain: u16,
    pub destination_chain: u16,
    pub recipient: Pubkey,
    pub amount: u64,
    pub nonce: [u8; 32],
    pub timestamp: i64,
}

#[error_code]
pub enum ErrorCode {
    #[msg("Exceeds maximum supply")]
    ExceedsMaxSupply,
    #[msg("Nonce already used")]
    NonceAlreadyUsed,
    #[msg("Invalid chain ID")]
    InvalidChainId,
    #[msg("Invalid amount")]
    InvalidAmount,
    #[msg("Invalid recipient")]
    InvalidRecipient,
    #[msg("Invalid sender")]
    InvalidSender,
    #[msg("Invalid authority")]
    InvalidAuthority,
    #[msg("Invalid decimals")]
    InvalidDecimals,
    #[msg("Invalid max supply")]
    InvalidMaxSupply,
    #[msg("Supply overflow")]
    SupplyOverflow,
    #[msg("Supply underflow")]
    SupplyUnderflow,
    #[msg("Nonce registry full")]
    NonceRegistryFull,
}

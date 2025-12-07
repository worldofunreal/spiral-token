use anchor_lang::prelude::*;
use anchor_spl::token::{self, Mint, Token, TokenAccount, Transfer};

declare_id!("SP1RAL111111111111111111111111111111111");

#[program]
pub mod spiral_token {
    use super::*;

    pub fn initialize_mint(
        ctx: Context<InitializeMint>,
        decimals: u8,
        max_supply: u64,
    ) -> Result<()> {
        let mint = &ctx.accounts.mint;
        let token_program = &ctx.accounts.token_program;

        // Initialize the mint
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

        Ok(())
    }

    pub fn mint_tokens(
        ctx: Context<MintTokens>,
        amount: u64,
    ) -> Result<()> {
        let mint_data = &mut ctx.accounts.mint_data;
        
        // Check if we're exceeding max supply
        require!(
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
        mint_data.current_supply += amount;

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
        let mint_data = &mut ctx.accounts.mint_data;
        
        // Burn tokens from sender
        let cpi_accounts = token::Burn {
            mint: ctx.accounts.mint.to_account_info(),
            from: ctx.accounts.sender.to_account_info(),
            authority: ctx.accounts.sender_authority.to_account_info(),
        };
        let cpi_program = ctx.accounts.token_program.to_account_info();
        let cpi_ctx = CpiContext::new(cpi_program, cpi_accounts);
        token::burn(cpi_ctx, amount)?;

        // Update supply
        mint_data.current_supply -= amount;

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

    pub fn receive_cross_chain_transfer(
        ctx: Context<ReceiveCrossChainTransfer>,
        source_chain: u16,
        sender: Pubkey,
        recipient: Pubkey,
        amount: u64,
        nonce: [u8; 32],
    ) -> Result<()> {
        let mint_data = &mut ctx.accounts.mint_data;
        
        // Check if nonce has been used
        require!(
            !ctx.accounts.nonce_registry.is_nonce_used(nonce),
            ErrorCode::NonceAlreadyUsed
        );

        // Mark nonce as used
        ctx.accounts.nonce_registry.mark_nonce_used(nonce)?;

        // Check if we're exceeding max supply
        require!(
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

        // Update supply
        mint_data.current_supply += amount;

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
        mint::decimals = 8,
        mint::authority = authority,
    )]
    pub mint: Account<'info, Mint>,
    
    #[account(
        init,
        payer = authority,
        space = 8 + 32 + 8 + 8,
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
pub struct ReceiveCrossChainTransfer<'info> {
    #[account(mut)]
    pub mint: Account<'info, Mint>,
    
    #[account(mut)]
    pub mint_data: Account<'info, MintData>,
    
    #[account(mut)]
    pub recipient: Account<'info, TokenAccount>,
    
    #[account(mut)]
    pub nonce_registry: Account<'info, NonceRegistry>,
    
    pub authority: Signer<'info>,
    pub token_program: Program<'info, Token>,
}

#[account]
pub struct MintData {
    pub max_supply: u64,
    pub current_supply: u64,
    pub authority: Pubkey,
}

#[account]
pub struct NonceRegistry {
    pub used_nonces: Vec<[u8; 32]>,
}

impl NonceRegistry {
    pub fn is_nonce_used(&self, nonce: [u8; 32]) -> bool {
        self.used_nonces.contains(&nonce)
    }

    pub fn mark_nonce_used(&mut self, nonce: [u8; 32]) -> Result<()> {
        if self.is_nonce_used(nonce) {
            return Err(ErrorCode::NonceAlreadyUsed.into());
        }
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
}
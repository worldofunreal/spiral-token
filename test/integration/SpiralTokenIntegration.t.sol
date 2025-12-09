// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {SpiralToken} from "../../ethereum/SpiralToken.sol";

/**
 * @title SpiralTokenIntegration
 * @notice Integration tests with real LayerZero endpoints on testnets
 * @dev These tests require:
 *      - Testnet RPC URLs in .env.testnet
 *      - Private key with testnet ETH
 *      - Real LayerZero endpoint addresses
 * 
 * To run:
 *   forge test --match-contract SpiralTokenIntegration --fork-url $SEPOLIA_RPC_URL -vvv
 */
contract SpiralTokenIntegration is Test {
    SpiralToken public spiralToken;
    
    // LayerZero Endpoint addresses (testnet)
    address constant SEPOLIA_LZ_ENDPOINT = 0x6EDCE65403992e310A62460808c4b910D972f10f;
    address constant MUMBAI_LZ_ENDPOINT = 0xF69186dfBa60dDB133E91e9A4b6473627ef1D236;
    
    // Testnet chain IDs
    uint16 constant SEPOLIA_CHAIN_ID = 40161;
    uint16 constant MUMBAI_CHAIN_ID = 40109;
    
    address public deployer;
    address public user;
    
    string constant TOKEN_NAME = "Spiral Token";
    string constant TOKEN_SYMBOL = "SPIRAL";
    uint256 constant INITIAL_SUPPLY = 1_000_000; // 1 million tokens
    
    function setUp() public {
        // Load testnet configuration
        // Note: In real integration tests, you'd load from .env.testnet
        // For now, this is a template that can be customized
        
        deployer = address(this);
        user = address(0x1234);
        
        // Deploy contract (in real test, this would be on testnet)
        // For integration tests, you may want to use a pre-deployed contract
        spiralToken = new SpiralToken(
            SEPOLIA_LZ_ENDPOINT,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            INITIAL_SUPPLY
        );
    }
    
    /**
     * @notice Test cross-chain transfer on testnet
     * @dev This test requires:
     *      - Contract deployed on Sepolia
     *      - Trusted remote configured for Mumbai
     *      - Testnet ETH for gas
     */
    function test_Integration_CrossChainTransfer_SepoliaToMumbai() public {
        // Skip if not on fork
        if (block.chainid != 11155111) {
            return; // Sepolia chain ID
        }
        
        // Set trusted remote for Mumbai
        bytes memory mumbaiRemote = abi.encodePacked(address(0x5678)); // Replace with actual Mumbai contract
        spiralToken.setTrustedRemote(MUMBAI_CHAIN_ID, mumbaiRemote);
        
        // User has tokens
        uint256 transferAmount = 100 * 10**18;
        require(spiralToken.balanceOf(deployer) >= transferAmount, "Insufficient balance");
        
        // Estimate fee
        bytes memory recipient = abi.encodePacked(user);
        (uint256 nativeFee, uint256 zroFee) = spiralToken.estimateFee(
            MUMBAI_CHAIN_ID,
            recipient,
            transferAmount,
            false,
            ""
        );
        
        // Perform cross-chain transfer
        uint256 balanceBefore = spiralToken.balanceOf(deployer);
        uint256 totalSupplyBefore = spiralToken.totalSupply();
        
        spiralToken.crossChainTransfer{value: nativeFee}(
            MUMBAI_CHAIN_ID,
            recipient,
            transferAmount,
            address(0),
            ""
        );
        
        // Verify burn
        assertEq(spiralToken.balanceOf(deployer), balanceBefore - transferAmount);
        assertEq(spiralToken.totalSupply(), totalSupplyBefore - transferAmount);
    }
    
    /**
     * @notice Test fee estimation accuracy
     */
    function test_Integration_FeeEstimation() public {
        if (block.chainid != 11155111) {
            return;
        }
        
        bytes memory recipient = abi.encodePacked(user);
        uint256 amount = 100 * 10**18;
        
        (uint256 nativeFee, uint256 zroFee) = spiralToken.estimateFee(
            MUMBAI_CHAIN_ID,
            recipient,
            amount,
            false,
            ""
        );
        
        // Fee should be non-zero
        assertGt(nativeFee, 0, "Fee should be greater than zero");
        
        // ZRO fee should be zero if not using ZRO
        assertEq(zroFee, 0, "ZRO fee should be zero");
    }
    
    /**
     * @notice Test that trusted remote validation works
     */
    function test_Integration_TrustedRemoteValidation() public {
        if (block.chainid != 11155111) {
            return;
        }
        
        // Try to transfer to untrusted chain - should revert
        bytes memory recipient = abi.encodePacked(user);
        uint256 amount = 100 * 10**18;
        
        vm.expectRevert("Destination chain not trusted");
        spiralToken.crossChainTransfer{value: 0}(
            uint16(65535), // Non-existent chain ID (max uint16)
            recipient,
            amount,
            address(0),
            ""
        );
    }
    
    /**
     * @notice Test pause functionality on testnet
     */
    function test_Integration_PauseFunctionality() public {
        if (block.chainid != 11155111) {
            return;
        }
        
        // Pause contract
        spiralToken.pause();
        assertTrue(spiralToken.paused(), "Contract should be paused");
        
        // Try to transfer - should revert
        bytes memory recipient = abi.encodePacked(user);
        uint256 amount = 100 * 10**18;
        
        vm.expectRevert();
        spiralToken.crossChainTransfer(
            MUMBAI_CHAIN_ID,
            recipient,
            amount,
            address(0),
            ""
        );
        
        // Unpause
        spiralToken.unpause();
        assertFalse(spiralToken.paused(), "Contract should be unpaused");
    }
    
    /**
     * @notice Test event emission
     */
    function test_Integration_EventEmission() public {
        if (block.chainid != 11155111) {
            return;
        }
        
        // Set up trusted remote
        bytes memory mumbaiRemote = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(MUMBAI_CHAIN_ID, mumbaiRemote);
        
        bytes memory recipient = abi.encodePacked(user);
        uint256 amount = 100 * 10**18;
        (uint256 nativeFee, uint256 zroFee) = spiralToken.estimateFee(
            MUMBAI_CHAIN_ID,
            recipient,
            amount,
            false,
            ""
        );
        
        // Expect CrossChainTransfer event
        vm.expectEmit(true, true, true, true);
        emit SpiralToken.CrossChainTransfer(
            MUMBAI_CHAIN_ID,
            recipient,
            amount,
            bytes32(0) // Nonce will be 0 for first transfer
        );
        
        spiralToken.crossChainTransfer{value: nativeFee}(
            MUMBAI_CHAIN_ID,
            recipient,
            amount,
            address(0),
            ""
        );
    }
}


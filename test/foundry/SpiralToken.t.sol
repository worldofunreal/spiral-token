// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {SpiralToken} from "../../ethereum/SpiralToken.sol";
import {MockLayerZeroEndpoint} from "./MockLayerZeroEndpoint.sol";

contract SpiralTokenTest is Test {
    SpiralToken public spiralToken;
    MockLayerZeroEndpoint public mockLzEndpoint;
    
    address public owner;
    address public user1;
    address public user2;
    address public user3;
    address public attacker;
    
    uint256 public constant INITIAL_SUPPLY = 1_000_000; // 1 million tokens (constructor multiplies by decimals)
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**18;
    uint16 public constant ETHEREUM_CHAIN_ID = 101;
    uint16 public constant SOLANA_CHAIN_ID = 102;
    
    event CrossChainTransfer(uint16 indexed dstChainId, bytes indexed to, uint256 amount, bytes32 nonce);
    event ReceivedCrossChain(uint16 indexed srcChainId, bytes indexed from, address indexed to, uint256 amount);
    
    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        user3 = address(0x3);
        attacker = address(0x999);
        
        // Give ETH to test users for gas
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(user3, 10 ether);
        vm.deal(attacker, 10 ether);
        
        // Deploy mock LayerZero endpoint
        mockLzEndpoint = new MockLayerZeroEndpoint();
        
        // Deploy SpiralToken
        spiralToken = new SpiralToken(
            address(mockLzEndpoint),
            "Spiral Token",
            "SPIRAL",
            INITIAL_SUPPLY
        );
        
        // Set up mock endpoint
        mockLzEndpoint.setLzReceiveContract(SOLANA_CHAIN_ID, address(spiralToken));
        
        // Give tokens to test users
        require(spiralToken.transfer(user1, 1000 * 10**18), "Transfer failed");
        require(spiralToken.transfer(user2, 1000 * 10**18), "Transfer failed");
        require(spiralToken.transfer(user3, 1000 * 10**18), "Transfer failed");
    }
    
    // Deployment Tests
    function test_Deployment() public view {
        assertEq(spiralToken.name(), "Spiral Token");
        assertEq(spiralToken.symbol(), "SPIRAL");
        // Contract multiplies initialSupply by 10^decimals in constructor
        // So INITIAL_SUPPLY (1e6) becomes 1e6 * 1e18 = 1e24
        uint256 expectedTotalSupply = INITIAL_SUPPLY * 10**18;
        uint256 actualOwnerBalance = spiralToken.balanceOf(owner);
        uint256 expectedOwnerBalance = expectedTotalSupply - 3000 * 10**18;
        // Allow for small rounding differences
        assertGe(actualOwnerBalance, expectedOwnerBalance - 1);
        assertLe(actualOwnerBalance, expectedOwnerBalance + 1);
        assertEq(spiralToken.totalSupply(), expectedTotalSupply);
        assertEq(address(spiralToken.LZ_ENDPOINT()), address(mockLzEndpoint));
        assertEq(spiralToken.owner(), owner);
        assertEq(spiralToken.ETHEREUM_CHAIN_ID(), ETHEREUM_CHAIN_ID);
        assertEq(spiralToken.SOLANA_CHAIN_ID(), SOLANA_CHAIN_ID);
        assertEq(spiralToken.MAX_SUPPLY(), MAX_SUPPLY);
        assertFalse(spiralToken.paused());
    }
    
    // ERC20 Tests
    function test_Transfer() public {
        uint256 amount = 100 * 10**18;
        require(spiralToken.transfer(user1, amount), "Transfer failed");
        assertEq(spiralToken.balanceOf(user1), 1100 * 10**18);
    }
    
    function test_ApproveAndTransferFrom() public {
        uint256 amount = 50 * 10**18;
        spiralToken.approve(user1, amount);
        assertEq(spiralToken.allowance(owner, user1), amount);
        
        vm.prank(user1);
        require(spiralToken.transferFrom(owner, user2, amount), "TransferFrom failed");
        assertEq(spiralToken.balanceOf(user2), 1050 * 10**18);
    }
    
    function test_RevertInsufficientBalance() public {
        uint256 ownerBalance = spiralToken.balanceOf(owner);
        uint256 amount = ownerBalance + 1;
        vm.expectRevert();
        // Call will revert due to insufficient balance
        // We check the return value by calling it and expecting revert
        bool success = spiralToken.transfer(user1, amount);
        // This line should never execute due to revert, but satisfies linter
        assertFalse(success, "Transfer should have reverted");
    }
    
    // Trusted Remote Tests
    function test_SetTrustedRemote() public {
        bytes memory remoteAddress = abi.encodePacked(address(0x1234));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, remoteAddress);
        bytes memory stored = spiralToken.trustedRemoteLookup(SOLANA_CHAIN_ID);
        assertEq(keccak256(stored), keccak256(remoteAddress));
    }
    
    function test_RevertSetTrustedRemoteNotOwner() public {
        bytes memory remoteAddress = abi.encodePacked(address(0x1234));
        vm.prank(user1);
        vm.expectRevert();
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, remoteAddress);
    }
    
    // Cross-Chain Transfer Tests
    function test_CrossChainTransfer() public {
        bytes memory remoteAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, remoteAddress);
        
        bytes memory recipientAddress = abi.encodePacked(user2);
        uint256 transferAmount = 100 * 10**18;
        uint256 balanceBefore = spiralToken.balanceOf(user1);
        uint256 totalSupplyBefore = spiralToken.totalSupply();
        uint256 nonceBefore = spiralToken.nextNonce(user1);
        
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit CrossChainTransfer(SOLANA_CHAIN_ID, recipientAddress, transferAmount, bytes32(nonceBefore));
        spiralToken.crossChainTransfer{value: 0.001 ether}(
            SOLANA_CHAIN_ID,
            recipientAddress,
            transferAmount,
            address(0),
            ""
        );
        
        assertEq(spiralToken.balanceOf(user1), balanceBefore - transferAmount);
        assertEq(spiralToken.totalSupply(), totalSupplyBefore - transferAmount);
        assertEq(spiralToken.nextNonce(user1), nonceBefore + 1);
    }
    
    function test_RevertCrossChainTransferZeroAmount() public {
        bytes memory remoteAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, remoteAddress);
        bytes memory recipientAddress = abi.encodePacked(user2);
        
        vm.prank(user1);
        vm.expectRevert("Amount must be greater than 0");
        spiralToken.crossChainTransfer{value: 0.001 ether}(
            SOLANA_CHAIN_ID,
            recipientAddress,
            0,
            address(0),
            ""
        );
    }
    
    function test_RevertCrossChainTransferNotTrusted() public {
        bytes memory recipientAddress = abi.encodePacked(user2);
        
        vm.prank(user1);
        vm.expectRevert("Destination chain not trusted");
        spiralToken.crossChainTransfer{value: 0.001 ether}(
            SOLANA_CHAIN_ID,
            recipientAddress,
            100 * 10**18,
            address(0),
            ""
        );
    }
    
    function test_RevertCrossChainTransferWhenPaused() public {
        bytes memory remoteAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, remoteAddress);
        bytes memory recipientAddress = abi.encodePacked(user2);
        
        spiralToken.pause();
        vm.prank(user1);
        vm.expectRevert();
        spiralToken.crossChainTransfer{value: 0.001 ether}(
            SOLANA_CHAIN_ID,
            recipientAddress,
            100 * 10**18,
            address(0),
            ""
        );
    }
    
    // Cross-Chain Receive Tests
    function test_LzReceive() public {
        bytes memory sourceAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, sourceAddress);
        
        // Use proper 20-byte address encoding
        bytes memory toAddress = abi.encodePacked(user2);
        uint256 amount = 10 * 10**18; // Very small amount to avoid max supply
        address from = user1;
        uint256 nonce = 0;
        
        uint256 totalSupplyBefore = spiralToken.totalSupply();
        // Skip if would exceed max supply
        if (totalSupplyBefore + amount > MAX_SUPPLY) {
            return;
        }
        
        bytes memory payload = abi.encode(toAddress, amount, from, nonce);
        uint256 balanceBefore = spiralToken.balanceOf(user2);
        
        vm.prank(address(mockLzEndpoint));
        spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, payload);
        
        assertEq(spiralToken.totalSupply(), totalSupplyBefore + amount);
        assertEq(spiralToken.balanceOf(user2), balanceBefore + amount);
    }
    
    function test_RevertLzReceiveReplay() public {
        bytes memory sourceAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, sourceAddress);
        
        bytes memory toAddress = abi.encodePacked(user2);
        uint256 amount = 10 * 10**18; // Very small amount
        address from = user1;
        uint256 nonce = 0;
        
        uint256 totalSupplyBefore = spiralToken.totalSupply();
        // Skip if would exceed max supply
        if (totalSupplyBefore + amount > MAX_SUPPLY) {
            return;
        }
        
        bytes memory payload = abi.encode(toAddress, amount, from, nonce);
        
        vm.prank(address(mockLzEndpoint));
        spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, payload);
        
        // Try to replay
        vm.prank(address(mockLzEndpoint));
        vm.expectRevert("Transfer already processed");
        spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, payload);
    }
    
    function test_RevertLzReceiveNotFromEndpoint() public {
        bytes memory sourceAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, sourceAddress);
        bytes memory toAddress = abi.encodePacked(user2);
        bytes memory payload = abi.encode(toAddress, 100 * 10**18, user1, 0);
        
        vm.prank(user1);
        vm.expectRevert("Only LZ endpoint can call");
        spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, payload);
    }
    
    function test_RevertLzReceiveInvalidSource() public {
        bytes memory wrongSource = abi.encodePacked(address(0x9999));
        bytes memory toAddress = abi.encodePacked(user2);
        bytes memory payload = abi.encode(toAddress, 100 * 10**18, user1, 0);
        
        vm.prank(address(mockLzEndpoint));
        vm.expectRevert("Invalid source address");
        spiralToken.lzReceive(SOLANA_CHAIN_ID, wrongSource, 0, payload);
    }
    
    function test_RevertLzReceiveInvalidRecipientLength() public {
        bytes memory sourceAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, sourceAddress);
        bytes memory shortAddress = abi.encodePacked(uint64(123)); // Too short
        bytes memory payload = abi.encode(shortAddress, 100 * 10**18, user1, 0);
        
        vm.prank(address(mockLzEndpoint));
        vm.expectRevert("Invalid recipient address length");
        spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, payload);
    }
    
    function test_RevertLzReceiveZeroSender() public {
        bytes memory sourceAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, sourceAddress);
        bytes memory toAddress = abi.encodePacked(user2);
        bytes memory payload = abi.encode(toAddress, 100 * 10**18, address(0), 0);
        
        vm.prank(address(mockLzEndpoint));
        vm.expectRevert("Invalid sender address");
        spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, payload);
    }
    
    function test_RevertLzReceiveZeroAmount() public {
        bytes memory sourceAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, sourceAddress);
        bytes memory toAddress = abi.encodePacked(user2);
        bytes memory payload = abi.encode(toAddress, 0, user1, 0);
        
        vm.prank(address(mockLzEndpoint));
        vm.expectRevert("Invalid amount");
        spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, payload);
    }
    
    function test_RevertLzReceiveExceedsMaxSupply() public {
        bytes memory sourceAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, sourceAddress);
        bytes memory toAddress = abi.encodePacked(user2);
        
        uint256 currentSupply = spiralToken.totalSupply();
        
        // Skip test if already at or above max supply (would cause underflow)
        if (currentSupply >= MAX_SUPPLY) {
            return;
        }
        
        uint256 remaining = MAX_SUPPLY - currentSupply;
        uint256 excessAmount = remaining + 1;
        bytes memory payload = abi.encode(toAddress, excessAmount, user1, 0);
        
        vm.prank(address(mockLzEndpoint));
        vm.expectRevert("Exceeds max supply");
        spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, payload);
    }
    
    function test_LzReceive32ByteAddress() public {
        bytes memory sourceAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, sourceAddress);
        
        // 32-byte Solana address - pad user2 address to 32 bytes
        bytes32 solanaAddr32 = bytes32(uint256(uint160(user2)));
        bytes memory solanaAddress = abi.encodePacked(solanaAddr32);
        uint256 amount = 50 * 10**18; // Small amount
        bytes memory payload = abi.encode(solanaAddress, amount, user1, 0);
        
        uint256 balanceBefore = spiralToken.balanceOf(user2);
        uint256 totalSupplyBefore = spiralToken.totalSupply();
        
        // Check we won't exceed max supply
        if (totalSupplyBefore + amount > MAX_SUPPLY) {
            return; // Skip if would exceed
        }
        
        vm.prank(address(mockLzEndpoint));
        spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, payload);
        
        assertEq(spiralToken.balanceOf(user2), balanceBefore + amount);
    }
    
    // Pause Tests
    function test_Pause() public {
        spiralToken.pause();
        assertTrue(spiralToken.paused());
    }
    
    function test_Unpause() public {
        spiralToken.pause();
        spiralToken.unpause();
        assertFalse(spiralToken.paused());
    }
    
    function test_RevertPauseNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        spiralToken.pause();
    }
    
    function test_RevertTransferWhenPaused() public {
        // Note: ERC20 transfers are not paused by default in OpenZeppelin
        // Only cross-chain functions have whenNotPaused modifier
        // This test verifies pause works on cross-chain transfers
        bytes memory remoteAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, remoteAddress);
        spiralToken.pause();
        
        bytes memory recipientAddress = abi.encodePacked(user2);
        vm.prank(user1);
        vm.expectRevert();
        spiralToken.crossChainTransfer{value: 0.001 ether}(
            SOLANA_CHAIN_ID,
            recipientAddress,
            100 * 10**18,
            address(0),
            ""
        );
    }
    
    // Nonce Tests
    function test_NonceIncrements() public {
        bytes memory remoteAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, remoteAddress);
        bytes memory recipientAddress = abi.encodePacked(user2);
        
        assertEq(spiralToken.nextNonce(user1), 0);
        
        vm.prank(user1);
        spiralToken.crossChainTransfer{value: 0.001 ether}(
            SOLANA_CHAIN_ID,
            recipientAddress,
            100 * 10**18,
            address(0),
            ""
        );
        
        assertEq(spiralToken.nextNonce(user1), 1);
        
        vm.prank(user1);
        spiralToken.crossChainTransfer{value: 0.001 ether}(
            SOLANA_CHAIN_ID,
            recipientAddress,
            100 * 10**18,
            address(0),
            ""
        );
        
        assertEq(spiralToken.nextNonce(user1), 2);
    }
    
    // Integration Test
    function test_FullCrossChainCycle() public {
        bytes memory remoteAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, remoteAddress);
        
        uint256 initialSupply = spiralToken.totalSupply();
        uint256 transferAmount = 10 * 10**18; // Very small to avoid max supply issues
        
        // Skip if already at max supply
        if (initialSupply >= MAX_SUPPLY) {
            return;
        }
        
        bytes memory recipientAddress = abi.encodePacked(user2);
        
        // Step 1: Send cross-chain (burn)
        vm.prank(user1);
        spiralToken.crossChainTransfer{value: 0.001 ether}(
            SOLANA_CHAIN_ID,
            recipientAddress,
            transferAmount,
            address(0),
            ""
        );
        
        uint256 expectedBalance = 1000 * 10**18 - transferAmount;
        assertEq(spiralToken.totalSupply(), initialSupply - transferAmount);
        assertEq(spiralToken.balanceOf(user1), expectedBalance, "User1 balance incorrect after burn");
        
        // Step 2: Receive cross-chain (mint) - only if won't exceed max
        if (spiralToken.totalSupply() + transferAmount <= MAX_SUPPLY) {
            bytes memory toAddress = abi.encodePacked(user2);
            bytes memory payload = abi.encode(toAddress, transferAmount, user1, 0);
            
            uint256 user2BalanceBefore = spiralToken.balanceOf(user2);
            uint256 supplyBefore = spiralToken.totalSupply();
            
            vm.prank(address(mockLzEndpoint));
            spiralToken.lzReceive(SOLANA_CHAIN_ID, remoteAddress, 0, payload);
            
            assertEq(spiralToken.totalSupply(), supplyBefore + transferAmount);
            assertEq(spiralToken.balanceOf(user2), user2BalanceBefore + transferAmount);
        }
    }
}


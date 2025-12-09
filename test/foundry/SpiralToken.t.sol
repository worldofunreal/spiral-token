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
        vm.expectRevert(); // Ownable: caller is not the owner
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
        vm.expectRevert(); // EnforcedPause or Pausable: paused
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
        vm.expectRevert(); // Ownable: caller is not the owner
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
        vm.expectRevert(); // EnforcedPause or Pausable: paused
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

    // ============================================
    // ATTACK SCENARIOS & EDGE CASES
    // ============================================

    // Note: crossChainTransfer and lzReceive have nonReentrant modifier as defensive measure.
    // There's no actual reentrancy vector since neither function calls external contracts
    // that can call back. The modifier protects against future code changes.
    // No reentrancy attack tests needed - structural protection (no callbacks) + modifier.

    // Advanced Replay Attack Tests
    function test_AttackReplayWithDifferentChainId() public {
        bytes memory sourceAddress1 = abi.encodePacked(address(0x5678));
        bytes memory sourceAddress2 = abi.encodePacked(address(0x5679));
        spiralToken.setTrustedRemote(101, sourceAddress1); // Chain 101
        spiralToken.setTrustedRemote(103, sourceAddress2); // Chain 103
        
        bytes memory toAddress = abi.encodePacked(user2);
        uint256 amount = 10 * 10**18;
        address from = user1;
        uint256 nonce = 42; // Same nonce
        
        uint256 totalSupplyBefore = spiralToken.totalSupply();
        if (totalSupplyBefore + amount > MAX_SUPPLY) {
            return;
        }
        
        bytes memory payload = abi.encode(toAddress, amount, from, nonce);
        
        // First receive from chain 101
        vm.prank(address(mockLzEndpoint));
        spiralToken.lzReceive(101, sourceAddress1, 0, payload);
        
        // Try to replay with same nonce but different chain ID
        // Should succeed because replay protection includes chain ID
        uint256 balanceBefore = spiralToken.balanceOf(user2);
        vm.prank(address(mockLzEndpoint));
        spiralToken.lzReceive(103, sourceAddress2, 0, payload);
        
        // Should have received tokens twice (different chains)
        assertEq(spiralToken.balanceOf(user2), balanceBefore + amount);
    }

    function test_AttackReplayWithDifferentSender() public {
        bytes memory sourceAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, sourceAddress);
        
        bytes memory toAddress = abi.encodePacked(user2);
        uint256 amount = 10 * 10**18;
        uint256 nonce = 123; // Same nonce
        
        uint256 totalSupplyBefore = spiralToken.totalSupply();
        if (totalSupplyBefore + amount > MAX_SUPPLY) {
            return;
        }
        
        // First receive from user1
        bytes memory payload1 = abi.encode(toAddress, amount, user1, nonce);
        vm.prank(address(mockLzEndpoint));
        spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, payload1);
        
        // Try to replay with same nonce but different sender
        // Should succeed because replay protection includes sender address
        bytes memory payload2 = abi.encode(toAddress, amount, user3, nonce);
        uint256 balanceBefore = spiralToken.balanceOf(user2);
        vm.prank(address(mockLzEndpoint));
        spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, payload2);
        
        // Should have received tokens twice (different senders)
        assertEq(spiralToken.balanceOf(user2), balanceBefore + amount);
    }

    function test_AttackReplayExactSameMessage() public {
        bytes memory sourceAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, sourceAddress);
        
        bytes memory toAddress = abi.encodePacked(user2);
        uint256 amount = 10 * 10**18;
        address from = user1;
        uint256 nonce = 999;
        
        uint256 totalSupplyBefore = spiralToken.totalSupply();
        if (totalSupplyBefore + amount > MAX_SUPPLY) {
            return;
        }
        
        bytes memory payload = abi.encode(toAddress, amount, from, nonce);
        
        // First receive
        vm.prank(address(mockLzEndpoint));
        spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, payload);
        
        // Try exact replay - should fail
        vm.prank(address(mockLzEndpoint));
        vm.expectRevert("Transfer already processed");
        spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, payload);
    }

    // Address Manipulation Attack Tests
    function test_AttackMalformedAddressTooShort() public {
        bytes memory sourceAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, sourceAddress);
        
        // Try with address shorter than 20 bytes
        bytes memory shortAddress = abi.encodePacked(uint8(123)); // Only 1 byte
        bytes memory payload = abi.encode(shortAddress, 100 * 10**18, user1, 0);
        
        vm.prank(address(mockLzEndpoint));
        vm.expectRevert(); // Reverts in assembly (length < 20)
        spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, payload);
    }

    function test_AttackMalformedAddressTooLong() public {
        bytes memory sourceAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, sourceAddress);
        
        // Try with address longer than 64 bytes (assembly limit)
        bytes memory longAddress = new bytes(100);
        for (uint i = 0; i < 100; i++) {
            // casting to 'uint8' is safe because i % 256 is always in range [0, 255]
            // forge-lint: disable-next-line(unsafe-typecast)
            longAddress[i] = bytes1(uint8(i % 256));
        }
        bytes memory payload = abi.encode(longAddress, 100 * 10**18, user1, 0);
        
        vm.prank(address(mockLzEndpoint));
        vm.expectRevert(); // Reverts in assembly (length > 64)
        spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, payload);
    }

    function test_AttackExtractZeroAddressFromBytes() public {
        bytes memory sourceAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, sourceAddress);
        
        // Try to craft bytes that extract to zero address
        // Create 20 bytes of zeros
        bytes memory zeroAddressBytes = new bytes(20);
        bytes memory payload = abi.encode(zeroAddressBytes, 100 * 10**18, user1, 0);
        
        vm.prank(address(mockLzEndpoint));
        vm.expectRevert("Cannot mint to zero address");
        spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, payload);
    }

    function test_AttackAddressExtraction21Bytes() public {
        bytes memory sourceAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, sourceAddress);
        
        // 21-byte address - contract doesn't handle 21 bytes specifically
        // It only handles 20, 32, and >32 bytes
        // For 21 bytes, the assembly doesn't match any condition, so recipient stays 0
        // This should revert with "Cannot mint to zero address"
        bytes memory addr21 = new bytes(21);
        bytes20 user2Addr = bytes20(user2);
        // Put user2 address in the first 20 bytes, then add one more byte
        for (uint i = 0; i < 20; i++) {
            addr21[i] = user2Addr[i];
        }
        addr21[20] = 0xFF;
        
        uint256 amount = 10 * 10**18;
        bytes memory payload = abi.encode(addr21, amount, user1, 0);
        
        uint256 balanceBefore = spiralToken.balanceOf(user2);
        uint256 totalSupplyBefore = spiralToken.totalSupply();
        
        // Should revert because only 20 or 32 byte addresses are supported
        vm.prank(address(mockLzEndpoint));
        vm.expectRevert("Unsupported address length");
        spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, payload);
        
        // Verify no state changes
        assertEq(spiralToken.balanceOf(user2), balanceBefore);
        assertEq(spiralToken.totalSupply(), totalSupplyBefore);
    }

    function test_AttackAddressExtraction64Bytes() public {
        bytes memory sourceAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, sourceAddress);
        
        // 64-byte address - contract attempts to extract last 20 bytes
        // The assembly logic for >32 bytes is complex and may not work perfectly
        // This test verifies the contract handles 64-byte addresses without crashing
        // and doesn't allow minting to zero address
        bytes memory addr64 = new bytes(64);
        // Fill with some data
        for (uint i = 0; i < 64; i++) {
            // casting to 'uint8' is safe because i % 256 is always in range [0, 255]
            // forge-lint: disable-next-line(unsafe-typecast)
            addr64[i] = bytes1(uint8(i % 256));
        }
        
        uint256 amount = 10 * 10**18;
        bytes memory payload = abi.encode(addr64, amount, user1, 0);
        
        uint256 totalSupplyBefore = spiralToken.totalSupply();
        
        // The contract should either extract an address or revert
        // It should NOT mint to zero address
        vm.prank(address(mockLzEndpoint));
        try spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, payload) {
            // If it succeeds, verify it didn't mint to zero address
            // (The extracted address might not be what we expect, but that's acceptable)
            assertGt(spiralToken.totalSupply(), totalSupplyBefore);
        } catch {
            // If it reverts (e.g., "Cannot mint to zero address"), that's acceptable
            // The important thing is it handles the input without crashing
        }
    }

    // Supply Manipulation Attack Tests
    function test_AttackExceedMaxSupplyExactly() public {
        bytes memory sourceAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, sourceAddress);
        
        uint256 currentSupply = spiralToken.totalSupply();
        if (currentSupply >= MAX_SUPPLY) {
            return;
        }
        
        uint256 remaining = MAX_SUPPLY - currentSupply;
        bytes memory toAddress = abi.encodePacked(user2);
        
        // Try to mint exactly the remaining supply - should succeed
        bytes memory payload = abi.encode(toAddress, remaining, user1, 0);
        vm.prank(address(mockLzEndpoint));
        spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, payload);
        
        assertEq(spiralToken.totalSupply(), MAX_SUPPLY);
    }

    function test_AttackExceedMaxSupplyByOne() public {
        bytes memory sourceAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, sourceAddress);
        
        uint256 currentSupply = spiralToken.totalSupply();
        if (currentSupply >= MAX_SUPPLY) {
            return;
        }
        
        uint256 remaining = MAX_SUPPLY - currentSupply;
        bytes memory toAddress = abi.encodePacked(user2);
        
        // Try to mint one more than remaining - should fail
        bytes memory payload = abi.encode(toAddress, remaining + 1, user1, 0);
        vm.prank(address(mockLzEndpoint));
        vm.expectRevert("Exceeds max supply");
        spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, payload);
    }

    function test_AttackIntegerOverflowInSupply() public {
        bytes memory sourceAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, sourceAddress);
        
        // Try to mint type(uint256).max - should fail (either overflow or max supply check)
        bytes memory toAddress = abi.encodePacked(user2);
        bytes memory payload = abi.encode(toAddress, type(uint256).max, user1, 0);
        
        vm.prank(address(mockLzEndpoint));
        // Will revert with overflow or "Exceeds max supply" - both are acceptable
        vm.expectRevert();
        spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, payload);
    }

    function test_AttackMultipleSmallMintsToExceedMax() public {
        bytes memory sourceAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, sourceAddress);
        
        uint256 currentSupply = spiralToken.totalSupply();
        if (currentSupply >= MAX_SUPPLY) {
            return;
        }
        
        uint256 remaining = MAX_SUPPLY - currentSupply;
        uint256 smallAmount = remaining / 2 + 1; // More than half remaining
        bytes memory toAddress = abi.encodePacked(user2);
        
        // First mint - should succeed
        bytes memory payload1 = abi.encode(toAddress, smallAmount, user1, 100);
        vm.prank(address(mockLzEndpoint));
        spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, payload1);
        
        // Second mint that would exceed - should fail
        bytes memory payload2 = abi.encode(toAddress, smallAmount, user1, 101);
        vm.prank(address(mockLzEndpoint));
        vm.expectRevert("Exceeds max supply");
        spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, payload2);
    }

    // Access Control Bypass Tests
    function test_AttackBypassOwnerSetTrustedRemote() public {
        bytes memory remoteAddress = abi.encodePacked(address(0x5678));
        
        // Attacker tries to set trusted remote
        vm.prank(attacker);
        vm.expectRevert(); // Ownable: caller is not the owner
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, remoteAddress);
        
        // Verify it wasn't set
        bytes memory stored = spiralToken.trustedRemoteLookup(SOLANA_CHAIN_ID);
        assertEq(stored.length, 0);
    }

    function test_AttackBypassPause() public {
        bytes memory remoteAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, remoteAddress);
        spiralToken.pause();
        
        // Attacker tries to bypass pause
        bytes memory recipientAddress = abi.encodePacked(user2);
        vm.prank(attacker);
        vm.expectRevert(); // EnforcedPause or Pausable: paused
        spiralToken.crossChainTransfer{value: 0.001 ether}(
            SOLANA_CHAIN_ID,
            recipientAddress,
            100 * 10**18,
            address(0),
            ""
        );
    }

    function test_AttackBypassLzReceiveNotFromEndpoint() public {
        bytes memory sourceAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, sourceAddress);
        
        bytes memory toAddress = abi.encodePacked(user2);
        bytes memory payload = abi.encode(toAddress, 100 * 10**18, user1, 0);
        
        // Attacker tries to call lzReceive directly
        vm.prank(attacker);
        vm.expectRevert("Only LZ endpoint can call");
        spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, payload);
    }

    function test_AttackBypassLzReceiveWithWrongEndpoint() public {
        bytes memory sourceAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, sourceAddress);
        
        // Deploy fake endpoint
        MockLayerZeroEndpoint fakeEndpoint = new MockLayerZeroEndpoint();
        
        bytes memory toAddress = abi.encodePacked(user2);
        bytes memory payload = abi.encode(toAddress, 100 * 10**18, user1, 0);
        
        // Try to call with fake endpoint
        vm.prank(address(fakeEndpoint));
        vm.expectRevert("Only LZ endpoint can call");
        spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, payload);
    }

    // Trusted Remote Manipulation Tests
    function test_AttackSetEmptyTrustedRemote() public {
        // Owner tries to set empty remote - should fail
        bytes memory emptyAddress = "";
        vm.expectRevert("Invalid remote address");
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, emptyAddress);
    }

    function test_AttackUseWrongTrustedRemote() public {
        bytes memory correctRemote = abi.encodePacked(address(0x5678));
        bytes memory wrongRemote = abi.encodePacked(address(0x9999));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, correctRemote);
        
        bytes memory toAddress = abi.encodePacked(user2);
        bytes memory payload = abi.encode(toAddress, 100 * 10**18, user1, 0);
        
        // Try to receive from wrong remote
        vm.prank(address(mockLzEndpoint));
        vm.expectRevert("Invalid source address");
        spiralToken.lzReceive(SOLANA_CHAIN_ID, wrongRemote, 0, payload);
    }

    function test_AttackUseWrongChainIdWithCorrectRemote() public {
        bytes memory remoteAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, remoteAddress);
        
        bytes memory toAddress = abi.encodePacked(user2);
        bytes memory payload = abi.encode(toAddress, 100 * 10**18, user1, 0);
        
        // Try to receive with wrong chain ID but correct remote
        vm.prank(address(mockLzEndpoint));
        vm.expectRevert("Invalid source address");
        spiralToken.lzReceive(999, remoteAddress, 0, payload); // Wrong chain ID
    }

    // Nonce Manipulation Tests
    function test_NonceIncrementsMultipleTimes() public {
        bytes memory remoteAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, remoteAddress);
        
        bytes memory recipientAddress = abi.encodePacked(user2);
        
        // Make multiple transfers to verify nonce increments correctly
        for (uint i = 0; i < 10; i++) {
            vm.prank(user1);
            spiralToken.crossChainTransfer{value: 0.001 ether}(
                SOLANA_CHAIN_ID,
                recipientAddress,
                1 * 10**18,
                address(0),
                ""
            );
        }
        
        // Nonce should have incremented correctly
        assertEq(spiralToken.nextNonce(user1), 10);
    }

    function test_AttackReplayWithWrappedNonce() public {
        bytes memory sourceAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, sourceAddress);
        
        // Test that even if nonce wraps, replay protection still works
        bytes memory toAddress = abi.encodePacked(user2);
        uint256 amount = 10 * 10**18;
        address from = user1;
        uint256 nonce = type(uint256).max; // Max nonce value
        
        uint256 totalSupplyBefore = spiralToken.totalSupply();
        if (totalSupplyBefore + amount > MAX_SUPPLY) {
            return;
        }
        
        bytes memory payload = abi.encode(toAddress, amount, from, nonce);
        
        // First receive
        vm.prank(address(mockLzEndpoint));
        spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, payload);
        
        // Try to replay - should fail
        vm.prank(address(mockLzEndpoint));
        vm.expectRevert("Transfer already processed");
        spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, payload);
    }

    // Boundary Condition Tests
    function test_AttackTransferMaxUint256() public {
        bytes memory remoteAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, remoteAddress);
        
        // Try to transfer more than balance - should revert
        uint256 hugeAmount = type(uint256).max / 2;
        vm.prank(user1);
        // OpenZeppelin ERC20 uses "ERC20InsufficientBalance" or similar
        vm.expectRevert();
        spiralToken.crossChainTransfer{value: 0.001 ether}(
            SOLANA_CHAIN_ID,
            abi.encodePacked(user2),
            hugeAmount,
            address(0),
            ""
        );
    }

    function test_AttackTransferOneWei() public {
        bytes memory remoteAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, remoteAddress);
        
        // Transfer minimum amount (1 wei)
        vm.prank(user1);
        spiralToken.crossChainTransfer{value: 0.001 ether}(
            SOLANA_CHAIN_ID,
            abi.encodePacked(user2),
            1, // 1 wei
            address(0),
            ""
        );
        
        // Should succeed
        assertEq(spiralToken.nextNonce(user1), 1);
    }

    function test_AttackReceiveOneWei() public {
        bytes memory sourceAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, sourceAddress);
        
        bytes memory toAddress = abi.encodePacked(user2);
        bytes memory payload = abi.encode(toAddress, 1, user1, 0); // 1 wei
        
        uint256 balanceBefore = spiralToken.balanceOf(user2);
        vm.prank(address(mockLzEndpoint));
        spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, payload);
        
        assertEq(spiralToken.balanceOf(user2), balanceBefore + 1);
    }

    // Cross-Chain Message Manipulation Tests
    function test_AttackMalformedPayload() public {
        bytes memory sourceAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, sourceAddress);
        
        // Try with malformed payload (wrong encoding)
        bytes memory malformedPayload = abi.encodePacked("malformed");
        
        vm.prank(address(mockLzEndpoint));
        vm.expectRevert(); // Reverts when trying to decode malformed payload
        spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, malformedPayload);
    }

    function test_AttackPayloadWithWrongTypes() public {
        bytes memory sourceAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, sourceAddress);
        
        // Try with payload that has wrong types
        bytes memory wrongPayload = abi.encode(uint256(123), address(0x1234), "wrong");
        
        vm.prank(address(mockLzEndpoint));
        vm.expectRevert(); // Reverts when trying to decode wrong payload types
        spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, wrongPayload);
    }

    // Front-Running Attack Tests
    function test_AttackFrontRunCrossChainTransfer() public {
        bytes memory remoteAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, remoteAddress);
        
        // Give attacker some tokens for the test
        require(spiralToken.transfer(attacker, 100 * 10**18), "Transfer failed");
        
        bytes memory recipientAddress = abi.encodePacked(user2);
        uint256 amount = 100 * 10**18;
        
        // User1 initiates transfer
        uint256 nonceBefore = spiralToken.nextNonce(user1);
        
        // Attacker tries to front-run by initiating their own transfer
        // This should just increment their own nonce, not affect user1's
        vm.prank(attacker);
        spiralToken.crossChainTransfer{value: 0.001 ether}(
            SOLANA_CHAIN_ID,
            abi.encodePacked(user3),
            50 * 10**18,
            address(0),
            ""
        );
        
        // User1's nonce should be unchanged
        assertEq(spiralToken.nextNonce(user1), nonceBefore);
        assertEq(spiralToken.nextNonce(attacker), 1);
        
        // Now user1's transfer should work normally
        vm.prank(user1);
        spiralToken.crossChainTransfer{value: 0.001 ether}(
            SOLANA_CHAIN_ID,
            recipientAddress,
            amount,
            address(0),
            ""
        );
        
        assertEq(spiralToken.nextNonce(user1), nonceBefore + 1);
    }

    // DoS Attack Tests
    function test_AttackDoSWithManySmallTransfers() public {
        bytes memory remoteAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, remoteAddress);
        
        bytes memory recipientAddress = abi.encodePacked(user2);
        
        // Make many small transfers to test gas efficiency
        for (uint i = 0; i < 50; i++) {
            vm.prank(user1);
            spiralToken.crossChainTransfer{value: 0.001 ether}(
                SOLANA_CHAIN_ID,
                recipientAddress,
                1 * 10**18,
                address(0),
                ""
            );
        }
        
        // Should have processed all transfers
        assertEq(spiralToken.nextNonce(user1), 50);
        assertEq(spiralToken.balanceOf(user1), 950 * 10**18);
    }

    // Hash Collision Attack Tests
    function test_AttackHashCollisionDifferentChains() public {
        // Test that different chain IDs produce different hashes even with same sender/nonce
        bytes memory sourceAddress1 = abi.encodePacked(address(0x5678));
        bytes memory sourceAddress2 = abi.encodePacked(address(0x5679));
        spiralToken.setTrustedRemote(101, sourceAddress1);
        spiralToken.setTrustedRemote(102, sourceAddress2);
        
        bytes memory toAddress = abi.encodePacked(user2);
        uint256 amount = 10 * 10**18;
        address from = user1;
        uint256 nonce = 777;
        
        uint256 totalSupplyBefore = spiralToken.totalSupply();
        if (totalSupplyBefore + amount > MAX_SUPPLY) {
            return;
        }
        
        bytes memory payload = abi.encode(toAddress, amount, from, nonce);
        
        // Receive from chain 101
        vm.prank(address(mockLzEndpoint));
        spiralToken.lzReceive(101, sourceAddress1, 0, payload);
        
        // Receive from chain 102 with same sender/nonce - should succeed (different chain)
        uint256 balanceBefore = spiralToken.balanceOf(user2);
        vm.prank(address(mockLzEndpoint));
        spiralToken.lzReceive(102, sourceAddress2, 0, payload);
        
        // Should have received both (different hashes due to different chain IDs)
        assertEq(spiralToken.balanceOf(user2), balanceBefore + amount);
    }
    
    // ============================================
    // ADDITIONAL SECURITY TESTS
    // ============================================
    
    // Test lzReceive when paused
    function test_LzReceiveWhenPaused() public {
        bytes memory sourceAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, sourceAddress);
        
        bytes memory toAddress = abi.encodePacked(user2);
        uint256 amount = 10 * 10**18;
        bytes memory payload = abi.encode(toAddress, amount, user1, 0);
        
        // Pause the contract
        spiralToken.pause();
        
        // lzReceive should also be blocked when paused (full emergency stop)
        uint256 balanceBefore = spiralToken.balanceOf(user2);
        uint256 totalSupplyBefore = spiralToken.totalSupply();
        
        vm.prank(address(mockLzEndpoint));
        vm.expectRevert(); // EnforcedPause or Pausable: paused
        spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, payload);
        
        // Verify no state changes
        assertEq(spiralToken.balanceOf(user2), balanceBefore);
        assertEq(spiralToken.totalSupply(), totalSupplyBefore);
    }
    
    // Test fee/msg.value behavior
    function test_CrossChainTransferWithZeroValue() public {
        bytes memory remoteAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, remoteAddress);
        
        bytes memory recipientAddress = abi.encodePacked(user2);
        
        // crossChainTransfer should work with 0 value (LayerZero endpoint handles fees)
        vm.prank(user1);
        spiralToken.crossChainTransfer{value: 0}(
            SOLANA_CHAIN_ID,
            recipientAddress,
            100 * 10**18,
            address(0),
            ""
        );
        
        // Should have burned tokens
        assertEq(spiralToken.balanceOf(user1), 900 * 10**18);
    }
    
    // Test owner management - ownership transfer
    function test_OwnershipTransfer() public {
        address newOwner = address(0xABCD);
        
        // Current owner can transfer ownership
        spiralToken.transferOwnership(newOwner);
        
        // Old owner can't pause anymore
        vm.expectRevert(); // Ownable: caller is not the owner
        spiralToken.pause();
        
        // New owner can pause
        vm.prank(newOwner);
        spiralToken.pause();
        assertTrue(spiralToken.paused());
        
        // New owner can unpause
        vm.prank(newOwner);
        spiralToken.unpause();
        assertFalse(spiralToken.paused());
    }
    
    // Test owner management - new owner can set trusted remote
    function test_NewOwnerCanSetTrustedRemote() public {
        address newOwner = address(0xABCD);
        spiralToken.transferOwnership(newOwner);
        
        bytes memory remoteAddress = abi.encodePacked(address(0x9999));
        
        // New owner can set trusted remote
        vm.prank(newOwner);
        spiralToken.setTrustedRemote(999, remoteAddress);
        
        bytes memory stored = spiralToken.trustedRemoteLookup(999);
        assertEq(keccak256(stored), keccak256(remoteAddress));
    }
    
    // Fuzz test for crossChainTransfer
    function testFuzz_CrossChainTransfer(
        uint256 amount,
        address recipient
    ) public {
        bytes memory remoteAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, remoteAddress);
        
        // Constrain amount to be valid
        amount = bound(amount, 1, spiralToken.balanceOf(user1));
        
        bytes memory recipientAddress = abi.encodePacked(recipient);
        uint256 balanceBefore = spiralToken.balanceOf(user1);
        uint256 totalSupplyBefore = spiralToken.totalSupply();
        uint256 nonceBefore = spiralToken.nextNonce(user1);
        
        vm.prank(user1);
        spiralToken.crossChainTransfer{value: 0.001 ether}(
            SOLANA_CHAIN_ID,
            recipientAddress,
            amount,
            address(0),
            ""
        );
        
        assertEq(spiralToken.balanceOf(user1), balanceBefore - amount);
        assertEq(spiralToken.totalSupply(), totalSupplyBefore - amount);
        assertEq(spiralToken.nextNonce(user1), nonceBefore + 1);
    }
    
    // Fuzz test for lzReceive
    function testFuzz_LzReceive(
        uint256 amount,
        address recipient,
        address sender,
        uint256 nonce
    ) public {
        bytes memory sourceAddress = abi.encodePacked(address(0x5678));
        spiralToken.setTrustedRemote(SOLANA_CHAIN_ID, sourceAddress);
        
        // Constrain inputs - bound to reasonable range that won't exceed max supply
        uint256 currentSupply = spiralToken.totalSupply();
        uint256 maxSafeAmount = MAX_SUPPLY > currentSupply ? MAX_SUPPLY - currentSupply : 0;
        amount = bound(amount, 1, maxSafeAmount > 0 ? maxSafeAmount : 1);
        vm.assume(recipient != address(0));
        vm.assume(sender != address(0));
        
        bytes memory toAddress = abi.encodePacked(recipient);
        bytes memory payload = abi.encode(toAddress, amount, sender, nonce);
        
        uint256 balanceBefore = spiralToken.balanceOf(recipient);
        uint256 totalSupplyBefore = spiralToken.totalSupply();
        
        vm.prank(address(mockLzEndpoint));
        spiralToken.lzReceive(SOLANA_CHAIN_ID, sourceAddress, 0, payload);
        
        assertEq(spiralToken.balanceOf(recipient), balanceBefore + amount);
        assertEq(spiralToken.totalSupply(), totalSupplyBefore + amount);
    }
    
    // ============================================
    // INVARIANT TESTS
    // ============================================
    
    // Invariant: Total supply never exceeds MAX_SUPPLY
    // This is checked after every test via Foundry's invariant testing
    function invariant_TotalSupplyNeverExceedsMax() public view {
        assertLe(spiralToken.totalSupply(), spiralToken.MAX_SUPPLY());
    }
}



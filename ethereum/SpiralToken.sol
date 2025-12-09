// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol" as OZERC20;
import "@openzeppelin/contracts/access/Ownable.sol" as OZOwnable;
import "@openzeppelin/contracts/utils/Pausable.sol" as OZPausable;
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol" as OZReentrancyGuard;
import "@layerzerolabs/lz-evm-sdk-v1-0.7/contracts/interfaces/ILayerZeroEndpoint.sol" as LZEndpoint;
import "@layerzerolabs/lz-evm-sdk-v1-0.7/contracts/interfaces/ILayerZeroReceiver.sol" as LZReceiver;

contract SpiralToken is OZERC20.ERC20, OZOwnable.Ownable, OZPausable.Pausable, OZReentrancyGuard.ReentrancyGuard, LZReceiver.ILayerZeroReceiver {
    LZEndpoint.ILayerZeroEndpoint public immutable LZ_ENDPOINT;
    
    // Chain IDs for different networks
    uint16 public constant ETHEREUM_CHAIN_ID = 101;
    uint16 public constant SOLANA_CHAIN_ID = 102;
    
    // Maximum token supply (1 billion)
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**18;

    // Mapping to track trusted remote addresses
    mapping(uint16 => bytes) public trustedRemoteLookup;
    
    // Counter for user nonces to prevent replay and ensure ordering
    mapping(address => uint256) public nextNonce;
    
    // Mapping to prevent double-spending of received nonces
    mapping(bytes32 => bool) public usedTransferNonces;
    
    event CrossChainTransfer(
        uint16 indexed dstChainId,
        bytes indexed to,
        uint256 amount,
        bytes32 nonce
    );
    
    event ReceivedCrossChain(
        uint16 indexed srcChainId,
        bytes indexed from,
        address indexed to,
        uint256 amount
    );
    
    event TrustedRemoteSet(
        uint16 indexed remoteChainId,
        bytes remoteAddress
    );
    
    constructor(
        address _lzEndpoint,
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply
    ) OZERC20.ERC20(_name, _symbol) OZOwnable.Ownable(msg.sender) {
        require(_lzEndpoint != address(0), "Invalid endpoint");
        LZ_ENDPOINT = LZEndpoint.ILayerZeroEndpoint(_lzEndpoint);
        if (_initialSupply > 0) {
            uint256 totalInitialSupply = _initialSupply * (10 ** decimals());
            require(totalInitialSupply <= MAX_SUPPLY, "Exceeds max supply");
            require(totalInitialSupply / (10 ** decimals()) == _initialSupply, "Supply overflow");
            _mint(msg.sender, totalInitialSupply);
        }
    }
    
    function setTrustedRemote(
        uint16 _remoteChainId,
        bytes calldata _remoteAddress
    ) external onlyOwner {
        require(_remoteAddress.length > 0, "Invalid remote address");
        trustedRemoteLookup[_remoteChainId] = _remoteAddress;
        emit TrustedRemoteSet(_remoteChainId, _remoteAddress);
    }
    
    function crossChainTransfer(
        uint16 _dstChainId,
        bytes calldata _to,
        uint256 _amount,
        address _zroPaymentAddress,
        bytes calldata _adapterParams
    ) external payable whenNotPaused nonReentrant {
        require(_amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= _amount, "Insufficient balance");
        require(trustedRemoteLookup[_dstChainId].length > 0, "Destination chain not trusted");
        
        // Use a strictly increasing nonce for the user to prevent replay and ensure ordering
        uint256 nonce = nextNonce[msg.sender]++;
        
        // Burn tokens first (Checks-Effects-Interactions)
        _burn(msg.sender, _amount);
        
        // Encode payload with the user-specific nonce
        // Payload: (toAddress, amount, sourceSenderAddress, userNonce)
        // We include sender address and nonce so the destination can verify uniqueness
        // Note: abi.encode(address) pads to 32 bytes, we'll extract 20 bytes on decode
        bytes memory payload = abi.encode(_to, _amount, msg.sender, nonce);
        
        LZ_ENDPOINT.send{value: msg.value}(
            _dstChainId,
            trustedRemoteLookup[_dstChainId],
            payload,
            payable(msg.sender),
            _zroPaymentAddress,
            _adapterParams
        );
        
        emit CrossChainTransfer(_dstChainId, _to, _amount, bytes32(nonce));
    }
    
    function lzReceive(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 /* _nonce */,
        bytes calldata _payload
    ) external override whenNotPaused nonReentrant {
        require(msg.sender == address(LZ_ENDPOINT), "Only LZ endpoint can call");
        require(
            _srcAddress.length == trustedRemoteLookup[_srcChainId].length &&
            keccak256(_srcAddress) == keccak256(trustedRemoteLookup[_srcChainId]),
            "Invalid source address"
        );
        
        // Decode payload matching the encoding in crossChainTransfer
        // Payload: (toAddress, amount, sourceSenderAddress, userNonce)
        (bytes memory to, uint256 amount, address from, uint256 senderNonce) = abi.decode(
            _payload,
            (bytes, uint256, address, uint256)
        );
        
        // Validate inputs
        require(to.length >= 20, "Invalid recipient address length");
        require(from != address(0), "Invalid sender address");
        require(amount > 0, "Invalid amount");
        
        // Extract recipient address from bytes
        // Only accept 20-byte (EVM) or 32-byte (Solana) addresses for security
        require(to.length == 20 || to.length == 32, "Unsupported address length");
        
        address recipient;
        assembly {
            let dataLen := mload(to)    // Get length
            let dataPtr := add(to, 32)  // Skip length prefix to get to data
            
            // For 20-byte addresses: bytes are left-aligned in the first word
            // Shift right by 12 bytes (96 bits) to get the address
            if eq(dataLen, 20) {
                let word := mload(dataPtr)
                recipient := shr(96, word)
            }
            
            // For 32-byte addresses: address is right-aligned (last 20 bytes)
            if eq(dataLen, 32) {
                let word := mload(dataPtr)
                recipient := and(word, 0x000000000000000000000000ffffffffffffffffffffffffffffffffffffffff)
            }
        }
        
        require(recipient != address(0), "Cannot mint to zero address");

        // Generate a unique hash for this transfer to prevent replay
        // Include source chain, sender address, and nonce to ensure uniqueness
        // Use inline assembly for gas optimization
        bytes32 transferHash;
        assembly {
            // Pack: _srcChainId (2 bytes) + from (20 bytes) + senderNonce (32 bytes) = 54 bytes
            // We'll use a scratch space approach
            let ptr := mload(0x40) // Get free memory pointer
            mstore(ptr, shl(240, _srcChainId)) // Store chainId at start (left-aligned)
            mstore(add(ptr, 2), shl(96, from)) // Store address (left-aligned, 20 bytes)
            mstore(add(ptr, 22), senderNonce) // Store nonce (32 bytes)
            
            // Hash 54 bytes: chainId (2) + address (20) + nonce (32)
            transferHash := keccak256(ptr, 54)
            
            // Update free memory pointer (not strictly necessary but good practice)
            mstore(0x40, add(ptr, 64))
        }
        require(!usedTransferNonces[transferHash], "Transfer already processed");
        usedTransferNonces[transferHash] = true;
        
        // Supply cap check
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds max supply");
        
        _mint(recipient, amount);
        
        emit ReceivedCrossChain(_srcChainId, abi.encodePacked(from), recipient, amount);
    }
    
    function estimateFee(
        uint16 _dstChainId,
        bytes calldata _to,
        uint256 _amount,
        bool _useZro,
        bytes calldata _adapterParams
    ) external view returns (uint256 nativeFee, uint256 zroFee) {
        require(_amount > 0, "Amount must be greater than 0");
        require(_to.length >= 20, "Invalid recipient address length");
        require(trustedRemoteLookup[_dstChainId].length > 0, "Destination chain not trusted");
        
        // Use current nonce for estimation
        uint256 nonce = nextNonce[msg.sender];
        bytes memory payload = abi.encode(_to, _amount, msg.sender, nonce);
        return LZ_ENDPOINT.estimateFees(
            _dstChainId,
            address(this),
            payload,
            _useZro,
            _adapterParams
        );
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
    
    // Emergency function to withdraw any ETH that may be stuck in the contract
    // This can happen if LayerZero endpoint refunds ETH to this contract
    function withdrawEth(address payable _to) external onlyOwner {
        require(_to != address(0), "Invalid recipient");
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = _to.call{value: balance}("");
            require(success, "ETH transfer failed");
        }
    }
}
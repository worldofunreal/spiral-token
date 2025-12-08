// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@layerzerolabs/lz-evm-sdk-v1-0.7/contracts/interfaces/ILayerZeroEndpoint.sol";
import "@layerzerolabs/lz-evm-sdk-v1-0.7/contracts/interfaces/ILayerZeroReceiver.sol";

contract SpiralToken is ERC20, Ownable, Pausable, ILayerZeroReceiver {
    ILayerZeroEndpoint public immutable lzEndpoint;
    
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
    
    constructor(
        address _lzEndpoint,
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        lzEndpoint = ILayerZeroEndpoint(_lzEndpoint);
        if (_initialSupply > 0) {
            _mint(msg.sender, _initialSupply * (10 ** decimals()));
        }
    }
    
    function setTrustedRemote(
        uint16 _remoteChainId,
        bytes calldata _remoteAddress
    ) external onlyOwner {
        trustedRemoteLookup[_remoteChainId] = _remoteAddress;
    }
    
    function crossChainTransfer(
        uint16 _dstChainId,
        bytes calldata _to,
        uint256 _amount,
        address _zroPaymentAddress,
        bytes calldata _adapterParams
    ) external payable whenNotPaused {
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
        
        lzEndpoint.send{value: msg.value}(
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
    ) external override whenNotPaused {
        require(msg.sender == address(lzEndpoint), "Only LZ endpoint can call");
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
        
        // Extract recipient address from bytes (take last 20 bytes for EVM compatibility)
        // This handles both 20-byte EVM addresses and 32-byte Solana addresses
        address recipient;
        assembly {
            // For bytes memory, the first 32 bytes contain the length
            let dataPtr := add(to, 32) // Skip length prefix
            let dataLen := mload(to)    // Get length
            
            // If length > 20, take the last 20 bytes; otherwise take all bytes
            if gt(dataLen, 20) {
                // Take last 20 bytes (for Solana 32-byte addresses)
                dataPtr := add(dataPtr, sub(dataLen, 20))
            }
            recipient := mload(dataPtr)
            // Mask to 20 bytes (160 bits) - clear upper 12 bytes
            recipient := and(recipient, 0x000000000000000000000000ffffffffffffffffffffffffffffffffffffffff)
        }
        
        require(recipient != address(0), "Cannot mint to zero address");

        // Generate a unique hash for this transfer to prevent replay
        // Include source chain, sender address, and nonce to ensure uniqueness
        bytes32 transferHash = keccak256(abi.encodePacked(_srcChainId, from, senderNonce));
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
        // Use current nonce for estimation
        uint256 nonce = nextNonce[msg.sender];
        bytes memory payload = abi.encode(_to, _amount, msg.sender, nonce);
        return lzEndpoint.estimateFees(
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
}
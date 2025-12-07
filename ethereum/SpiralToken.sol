// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@layerzerolabs/lz-evm-sdk-v1-0.7/contracts/interfaces/ILayerZeroEndpoint.sol";
import "@layerzerolabs/lz-evm-sdk-v1-0.7/contracts/interfaces/ILayerZeroReceiver.sol";

contract SpiralToken is ERC20, Ownable, ILayerZeroReceiver {
    ILayerZeroEndpoint public immutable lzEndpoint;
    
    // Chain IDs for different networks
    uint16 public constant ETHEREUM_CHAIN_ID = 101;
    uint16 public constant SOLANA_CHAIN_ID = 102;
    
    // Mapping to track trusted remote addresses
    mapping(uint16 => bytes) public trustedRemoteLookup;
    
    // Mapping to prevent double-spending during cross-chain transfers
    mapping(bytes32 => bool) public usedNonces;
    
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
    ) external payable {
        require(_amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= _amount, "Insufficient balance");
        
        bytes32 nonce = keccak256(abi.encodePacked(
            block.timestamp,
            msg.sender,
            _dstChainId,
            _to,
            _amount
        ));
        
        require(!usedNonces[nonce], "Nonce already used");
        usedNonces[nonce] = true;
        
        _burn(msg.sender, _amount);
        
        bytes memory payload = abi.encode(_to, _amount, nonce);
        
        lzEndpoint.send{value: msg.value}(
            _dstChainId,
            trustedRemoteLookup[_dstChainId],
            payload,
            payable(msg.sender),
            _zroPaymentAddress,
            _adapterParams
        );
        
        emit CrossChainTransfer(_dstChainId, _to, _amount, nonce);
    }
    
    function lzReceive(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 /* _nonce */,
        bytes calldata _payload
    ) external override {
        require(msg.sender == address(lzEndpoint), "Only LZ endpoint can call");
        require(
            _srcAddress.length == trustedRemoteLookup[_srcChainId].length &&
            keccak256(_srcAddress) == keccak256(trustedRemoteLookup[_srcChainId]),
            "Invalid source address"
        );
        
        (bytes memory to, uint256 amount, bytes32 transferNonce) = abi.decode(
            _payload,
            (bytes, uint256, bytes32)
        );
        
        require(!usedNonces[transferNonce], "Transfer nonce already used");
        usedNonces[transferNonce] = true;
        
        address recipient = address(bytes20(to));
        _mint(recipient, amount);
        
        emit ReceivedCrossChain(_srcChainId, _srcAddress, recipient, amount);
    }
    
    function estimateFee(
        uint16 _dstChainId,
        bytes calldata _to,
        uint256 _amount,
        bool _useZro,
        bytes calldata _adapterParams
    ) external view returns (uint256 nativeFee, uint256 zroFee) {
        bytes memory payload = abi.encode(_to, _amount, bytes32(0));
        return lzEndpoint.estimateFees(
            _dstChainId,
            address(this),
            payload,
            _useZro,
            _adapterParams
        );
    }
}
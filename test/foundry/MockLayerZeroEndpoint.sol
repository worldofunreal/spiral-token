// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@layerzerolabs/lz-evm-sdk-v1-0.7/contracts/interfaces/ILayerZeroEndpoint.sol" as LZEndpoint;
import "@layerzerolabs/lz-evm-sdk-v1-0.7/contracts/interfaces/ILayerZeroReceiver.sol" as LZReceiver;

/**
 * @title MockLayerZeroEndpoint
 * @notice Mock implementation of ILayerZeroEndpoint for testing
 */
contract MockLayerZeroEndpoint is LZEndpoint.ILayerZeroEndpoint {
    mapping(uint16 => address) public lzReceiveContracts;
    mapping(uint16 => bytes) public trustedRemotes;
    
    uint64 public nonce;
    uint16 public chainId = 101;
    
    // Store sent messages for testing
    struct SentMessage {
        uint16 dstChainId;
        bytes destination;
        bytes payload;
        address refundAddress;
    }
    mapping(uint64 => SentMessage) public sentMessages;
    
    function send(
        uint16 _dstChainId,
        bytes calldata _destination,
        bytes calldata _payload,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes calldata _adapterParams
    ) external payable {
        // Store the destination contract for this chain
        address receiver = lzReceiveContracts[_dstChainId];
        require(receiver != address(0), "Receiver not set");
        
        // Store message details for testing
        sentMessages[nonce] = SentMessage({
            dstChainId: _dstChainId,
            destination: _destination,
            payload: _payload,
            refundAddress: _refundAddress
        });
        
        // Use parameters to avoid warnings
        if (_zroPaymentAddress != address(0)) {
            // ZRO payment address provided (for future use)
        }
        if (_adapterParams.length > 0) {
            // Adapter params provided (for future use)
        }
        
        // Simulate cross-chain message delivery
        nonce++;
    }
    
    // Helper function for tests to set the receiver contract
    function setLzReceiveContract(uint16 _chainId, address _receiver) external {
        lzReceiveContracts[_chainId] = _receiver;
    }
    
    // Helper function to simulate receiving a message
    function deliverMessage(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        address _receiver,
        bytes calldata _payload
    ) external {
        LZReceiver.ILayerZeroReceiver(_receiver).lzReceive(
            _srcChainId,
            _srcAddress,
            nonce++,
            _payload
        );
    }
    
    function estimateFees(
        uint16 _dstChainId,
        address _userApplication,
        bytes calldata _payload,
        bool _payInZro,
        bytes calldata _adapterParams
    ) external pure returns (uint256 nativeFee, uint256 zroFee) {
        // Use parameters to calculate mock fees
        uint256 baseFee = 0.001 ether;
        uint256 payloadFee = uint256(_payload.length) * 1 gwei;
        nativeFee = baseFee + payloadFee;
        
        // Use other parameters to avoid warnings
        if (_dstChainId > 0 && _userApplication != address(0)) {
            // Parameters validated
        }
        if (_payInZro) {
            zroFee = 1;
        }
        if (_adapterParams.length > 0) {
            // Adapter params considered
        }
        
        return (nativeFee, zroFee);
    }
    
    function getInboundNonce(uint16 _srcChainId, bytes calldata _srcAddress) external pure returns (uint64) {
        // Return stored nonce based on source
        if (_srcChainId > 0 && _srcAddress.length > 0) {
            return 0;
        }
        return 0;
    }
    
    function getOutboundNonce(uint16 _dstChainId, address _srcAddress) external pure returns (uint64) {
        // Return stored nonce based on destination
        if (_dstChainId > 0 && _srcAddress != address(0)) {
            return 0;
        }
        return 0;
    }
    
    function getChainId() external view returns (uint16) {
        return chainId;
    }
    
    function receivePayload(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        address _dstAddress,
        uint64 _nonce,
        uint _gasLimit,
        bytes calldata _payload
    ) external pure {
        // Store payload info for testing - use all parameters
        require(_srcChainId > 0, "Invalid chain");
        require(_dstAddress != address(0), "Invalid destination");
        require(_payload.length > 0, "Empty payload");
        require(_nonce > 0, "Invalid nonce");
        require(_gasLimit > 0, "Invalid gas");
        require(_srcAddress.length > 0, "Invalid source");
        // All parameters validated
    }
    
    function retryPayload(uint16 _srcChainId, bytes calldata _srcAddress, bytes calldata _payload) external pure {
        // Retry logic - use parameters
        require(_srcChainId > 0, "Invalid chain");
        require(_srcAddress.length > 0, "Invalid source");
        require(_payload.length > 0, "Empty payload");
        // Parameters validated for retry
    }
    
    function hasStoredPayload(uint16 _srcChainId, bytes calldata _srcAddress) external pure returns (bool) {
        // Check if payload exists - use parameters
        return _srcChainId > 0 && _srcAddress.length > 0 ? false : false;
    }
    
    function getSendLibraryAddress(address _userApplication) external pure returns (address) {
        // Return library address based on application
        if (_userApplication != address(0)) {
            return address(0);
        }
        return address(0);
    }
    
    function getReceiveLibraryAddress(address _userApplication) external pure returns (address) {
        // Return library address based on application
        if (_userApplication != address(0)) {
            return address(0);
        }
        return address(0);
    }
    
    function isSendingPayload() external pure returns (bool) {
        return false;
    }
    
    function isReceivingPayload() external pure returns (bool) {
        return false;
    }
    
    function getConfig(
        uint16 _version,
        uint16 _chainId,
        address _userApplication,
        uint _configType
    ) external pure returns (bytes memory) {
        // Return config based on parameters
        if (_version > 0 && _chainId > 0 && _userApplication != address(0) && _configType > 0) {
            return "";
        }
        return "";
    }
    
    function getSendVersion(address _userApplication) external pure returns (uint16) {
        // Return version based on application
        if (_userApplication != address(0)) {
            return 1;
        }
        return 1;
    }
    
    function getReceiveVersion(address _userApplication) external pure returns (uint16) {
        // Return version based on application
        if (_userApplication != address(0)) {
            return 1;
        }
        return 1;
    }
    
    // ILayerZeroUserApplicationConfig functions
    function setConfig(
        uint16 _version,
        uint16 _chainId,
        uint _configType,
        bytes calldata _config
    ) external pure {
        // Store config - use parameters
        require(_version > 0, "Invalid version");
        require(_chainId > 0, "Invalid chain");
        require(_configType > 0, "Invalid config type");
        require(_config.length > 0, "Empty config");
        // Config stored (mock implementation)
    }
    
    function setSendVersion(uint16 _version) external pure {
        // Set send version
        require(_version > 0, "Invalid version");
        // Version set (mock implementation)
    }
    
    function setReceiveVersion(uint16 _version) external pure {
        // Set receive version
        require(_version > 0, "Invalid version");
        // Version set (mock implementation)
    }
    
    function forceResumeReceive(uint16 _srcChainId, bytes calldata _srcAddress) external pure {
        // Force resume - use parameters
        require(_srcChainId > 0, "Invalid chain");
        require(_srcAddress.length > 0, "Invalid source");
        // Resume forced (mock implementation)
    }
}

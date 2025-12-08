// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@layerzerolabs/lz-evm-sdk-v1-0.7/contracts/interfaces/ILayerZeroEndpoint.sol";
import "@layerzerolabs/lz-evm-sdk-v1-0.7/contracts/interfaces/ILayerZeroReceiver.sol";

/**
 * @title MockLayerZeroEndpoint
 * @notice Mock implementation of ILayerZeroEndpoint for testing
 */
contract MockLayerZeroEndpoint is ILayerZeroEndpoint {
    mapping(uint16 => address) public lzReceiveContracts;
    mapping(uint16 => bytes) public trustedRemotes;
    
    uint64 public nonce;
    uint16 public chainId = 101;
    
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
        ILayerZeroReceiver(_receiver).lzReceive(
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
        bool _payInZRO,
        bytes calldata _adapterParams
    ) external pure returns (uint256 nativeFee, uint256 zroFee) {
        return (0.001 ether, 0);
    }
    
    function getInboundNonce(uint16 _srcChainId, bytes calldata _srcAddress) external pure returns (uint64) {
        return 0;
    }
    
    function getOutboundNonce(uint16 _dstChainId, address _srcAddress) external pure returns (uint64) {
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
    ) external {
        // Mock implementation
    }
    
    function retryPayload(uint16 _srcChainId, bytes calldata _srcAddress, bytes calldata _payload) external {
        // Mock implementation
    }
    
    function hasStoredPayload(uint16 _srcChainId, bytes calldata _srcAddress) external pure returns (bool) {
        return false;
    }
    
    function getSendLibraryAddress(address _userApplication) external pure returns (address) {
        return address(0);
    }
    
    function getReceiveLibraryAddress(address _userApplication) external pure returns (address) {
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
        return "";
    }
    
    function getSendVersion(address _userApplication) external pure returns (uint16) {
        return 1;
    }
    
    function getReceiveVersion(address _userApplication) external pure returns (uint16) {
        return 1;
    }
    
    // ILayerZeroUserApplicationConfig functions
    function setConfig(
        uint16 _version,
        uint16 _chainId,
        uint _configType,
        bytes calldata _config
    ) external {
        // Mock implementation
    }
    
    function setSendVersion(uint16 _version) external {
        // Mock implementation
    }
    
    function setReceiveVersion(uint16 _version) external {
        // Mock implementation
    }
    
    function forceResumeReceive(uint16 _srcChainId, bytes calldata _srcAddress) external {
        // Mock implementation
    }
}


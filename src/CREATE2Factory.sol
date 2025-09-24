// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title CREATE2Factory
 * @dev Minimal factory for deterministic CREATE2 deployments
 */
contract CREATE2Factory {
    event Deployed(address indexed deployed, bytes32 indexed salt);

    /**
     * @dev Deploys a contract using CREATE2
     * @param bytecode Contract bytecode
     * @param salt Salt for deterministic address
     * @return deployed Address of deployed contract
     */
    function deploy(bytes memory bytecode, bytes32 salt) external returns (address deployed) {
        assembly {
            deployed := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        require(deployed != address(0), "CREATE2 deployment failed");
        emit Deployed(deployed, salt);
    }

    /**
     * @dev Calculate CREATE2 address
     * @param bytecode Contract bytecode
     * @param salt Salt for deterministic address
     * @return calculated Address that would be created
     */
    function calculateAddress(bytes memory bytecode, bytes32 salt) external view returns (address) {
        if (bytecode.length == 0) {
            return address(0);
        }

        bytes32 bytecodeHash = keccak256(bytecode);
        bytes32 data = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, bytecodeHash));
        return address(uint160(uint256(data)));
    }
}

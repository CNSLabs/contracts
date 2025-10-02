// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";

/**
 * @title BaseScript
 * @notice Base contract for all deployment scripts with shared utilities
 * @dev Inherit from this instead of Script.sol directly to get common helpers
 */
abstract contract BaseScript is Script {
    // ============================================
    // Chain IDs
    // ============================================

    uint256 constant ETHEREUM_MAINNET = 1;
    uint256 constant ETHEREUM_SEPOLIA = 11155111;
    uint256 constant LINEA_MAINNET = 59144;
    uint256 constant LINEA_SEPOLIA = 59141;
    uint256 constant ANVIL = 31337;
    uint256 constant HARDHAT = 1337;

    // ============================================
    // Network Detection
    // ============================================

    /**
     * @notice Get human-readable network name from chain ID
     * @param chainId The chain ID to look up
     * @return The network name
     */
    function _getNetworkName(uint256 chainId) internal pure returns (string memory) {
        if (chainId == ETHEREUM_MAINNET) return "Ethereum Mainnet";
        if (chainId == ETHEREUM_SEPOLIA) return "Ethereum Sepolia";
        if (chainId == LINEA_MAINNET) return "Linea Mainnet";
        if (chainId == LINEA_SEPOLIA) return "Linea Sepolia";
        if (chainId == ANVIL) return "Local Anvil";
        if (chainId == HARDHAT) return "Local Hardhat";
        return string.concat("Unknown (Chain ID: ", vm.toString(chainId), ")");
    }

    /**
     * @notice Get Forge verification chain parameter
     * @param chainId The chain ID to look up
     * @return The --chain parameter for forge verify-contract
     */
    function _getChainParam(uint256 chainId) internal pure returns (string memory) {
        if (chainId == ETHEREUM_MAINNET) return "--chain mainnet";
        if (chainId == ETHEREUM_SEPOLIA) return "--chain sepolia";
        if (chainId == LINEA_MAINNET) return "--chain linea";
        if (chainId == LINEA_SEPOLIA) return "--chain linea-sepolia";
        return ""; // No automatic verification for unknown chains
    }

    /**
     * @notice Check if current chain is a mainnet
     * @return true if mainnet, false otherwise
     */
    function _isMainnet() internal view returns (bool) {
        return block.chainid == ETHEREUM_MAINNET || block.chainid == LINEA_MAINNET;
    }

    /**
     * @notice Check if current chain is a testnet
     * @return true if testnet, false otherwise
     */
    function _isTestnet() internal view returns (bool) {
        return block.chainid == ETHEREUM_SEPOLIA || block.chainid == LINEA_SEPOLIA;
    }

    /**
     * @notice Check if current chain is local dev environment
     * @return true if local, false otherwise
     */
    function _isLocalNetwork() internal view returns (bool) {
        return block.chainid == ANVIL || block.chainid == HARDHAT;
    }

    // ============================================
    // Logging Utilities
    // ============================================

    /**
     * @notice Log deployment info header
     */
    function _logDeploymentHeader(string memory title) internal view {
        console.log("\n=== %s ===", title);
        console.log("Network:", _getNetworkName(block.chainid));
        console.log("Chain ID:", block.chainid);
        console.log("Block:", block.number);
        console.log("Timestamp:", block.timestamp);
    }

    /**
     * @notice Log verification command for a deployed contract
     * @param contractAddress The deployed contract address
     * @param contractPath The contract path (e.g., "src/MyContract.sol:MyContract")
     */
    function _logVerificationCommand(address contractAddress, string memory contractPath) internal view {
        console.log("\n=== Verification Command ===");

        string memory chainParam = _getChainParam(block.chainid);

        if (bytes(chainParam).length > 0) {
            console.log("To verify this contract:");
            console.log(
                string.concat(
                    "forge verify-contract ",
                    vm.toString(contractAddress),
                    " ",
                    contractPath,
                    " ",
                    chainParam,
                    " --watch"
                )
            );
        } else {
            console.log("Manual verification required for this network");
            console.log("Contract address:", vm.toString(contractAddress));
        }
    }

    /**
     * @notice Log verification command with constructor args
     * @param contractAddress The deployed contract address
     * @param contractPath The contract path
     * @param constructorArgs The ABI-encoded constructor arguments
     */
    function _logVerificationCommandWithArgs(
        address contractAddress,
        string memory contractPath,
        bytes memory constructorArgs
    ) internal view {
        console.log("\n=== Verification Command ===");

        string memory chainParam = _getChainParam(block.chainid);

        if (bytes(chainParam).length > 0) {
            console.log("To verify this contract:");
            console.log(
                string.concat(
                    "forge verify-contract ",
                    vm.toString(contractAddress),
                    " ",
                    contractPath,
                    " ",
                    chainParam,
                    " --constructor-args ",
                    vm.toString(constructorArgs),
                    " --watch"
                )
            );
        } else {
            console.log("Manual verification required for this network");
            console.log("Contract address:", vm.toString(contractAddress));
        }
    }

    // ============================================
    // Safety Checks
    // ============================================

    /**
     * @notice Require explicit confirmation for mainnet deployments
     * @dev Set MAINNET_DEPLOYMENT_ALLOWED=true in .env to allow mainnet deployments
     */
    function _requireMainnetConfirmation() internal view {
        if (_isMainnet()) {
            require(
                vm.envOr("MAINNET_DEPLOYMENT_ALLOWED", false),
                "Mainnet deployment requires MAINNET_DEPLOYMENT_ALLOWED=true in .env"
            );
            console.log("[WARNING] Deploying to MAINNET");
        }
    }

    /**
     * @notice Validate that an address is not zero
     * @param addr The address to validate
     * @param name The name of the address (for error messages)
     */
    function _requireNonZeroAddress(address addr, string memory name) internal pure {
        require(addr != address(0), string.concat(name, " cannot be zero address"));
    }

    /**
     * @notice Validate that an address is a contract
     * @param addr The address to validate
     * @param name The name of the address (for error messages)
     */
    function _requireContract(address addr, string memory name) internal view {
        require(addr.code.length > 0, string.concat(name, " must be a contract"));
    }

    // ============================================
    // Environment Variable Helpers
    // ============================================

    /**
     * @notice Get deployer private key and address
     * @return privateKey The deployer's private key
     * @return deployerAddress The deployer's address
     */
    function _getDeployer() internal view returns (uint256 privateKey, address deployerAddress) {
        privateKey = vm.envUint("PRIVATE_KEY");
        deployerAddress = vm.addr(privateKey);
    }
}

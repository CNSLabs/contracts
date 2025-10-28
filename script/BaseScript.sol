// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "./ConfigLoader.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

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
        string memory rpcName = _getRpcEndpointName(chainId);
        if (bytes(rpcName).length == 0) return "";
        return string.concat("--chain ", rpcName);
    }

    /**
     * @notice Get RPC endpoint name for the given chain ID
     * @param chainId The chain ID to look up
     * @return The RPC endpoint name (e.g., "linea-sepolia", "mainnet")
     */
    function _getRpcEndpointName(uint256 chainId) internal pure returns (string memory) {
        if (chainId == ETHEREUM_MAINNET) return "mainnet";
        if (chainId == ETHEREUM_SEPOLIA) return "sepolia";
        if (chainId == LINEA_MAINNET) return "linea";
        if (chainId == LINEA_SEPOLIA) return "linea-sepolia";
        return "";
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

    /**
     * @notice Resolve environment name for config selection.
     * @dev Uses ENV; defaults to "dev".
     */
    function _getEnvName() internal view returns (string memory) {
        string memory fromEnv = vm.envOr("ENV", string(""));
        if (bytes(fromEnv).length != 0) return fromEnv;
        return "dev";
    }

    /**
     * @notice Resolve config file path as config/<ENV>.json where ENV from _getEnvName().
     */
    function _resolveConfigPath() internal view returns (string memory) {
        string memory envName = _getEnvName();
        return string.concat("config/", envName, ".json");
    }

    /**
     * @notice Load EnvConfig from resolved path or a provided env name
     */
    function _loadEnvConfig() internal view returns (EnvConfig memory cfg) {
        string memory path = _resolveConfigPath();
        return ConfigLoader.loadFromPath(vm, path);
    }

    function _loadEnvConfig(string memory envName) internal view returns (EnvConfig memory cfg) {
        if (bytes(envName).length != 0) {
            return ConfigLoader.loadEnv(vm, envName);
        }
        return _loadEnvConfig();
    }

    // ============================================
    // Broadcast Artifacts Helpers
    // ============================================

    /**
     * @notice Extract simple contract name from a possibly fully-qualified name (e.g., path:Name -> Name)
     */
    function _simpleContractName(string memory name) internal pure returns (string memory) {
        bytes memory b = bytes(name);
        int256 lastColon = -1;
        for (uint256 i = 0; i < b.length; i++) {
            if (b[i] == ":") {
                lastColon = int256(uint256(i));
            }
        }
        if (lastColon < 0) {
            return name;
        }
        uint256 start = uint256(lastColon) + 1;
        uint256 len = b.length - start;
        bytes memory out = new bytes(len);
        for (uint256 j = 0; j < len; j++) {
            out[j] = b[start + j];
        }
        return string(out);
    }

    /**
     * @notice Generic reader for Foundry broadcast run-latest.json to fetch the last deployed address for a contract
     * @param chainId The chain id subdirectory to look under
     * @param scriptBasename The script basename under broadcast/ (e.g., "1_DeployCNSTokenL1.s.sol")
     * @param desiredContractName The simple contract name to look for (e.g., "ShoTokenL1" or "ERC1967Proxy")
     */
    function _inferFromBroadcast(uint256 chainId, string memory scriptBasename, string memory desiredContractName)
        internal
        view
        returns (address)
    {
        if (chainId == 0) return address(0);
        string memory path = string.concat("broadcast/", scriptBasename, "/", vm.toString(chainId), "/run-latest.json");
        string memory json;
        try vm.readFile(path) returns (string memory contents) {
            json = contents;
        } catch {
            return address(0);
        }

        bytes32 desired = keccak256(bytes(desiredContractName));
        address found = address(0);
        for (uint256 i = 0; i < 256; i++) {
            string memory idx = vm.toString(i);
            string memory nameKey = string.concat(".transactions[", idx, "].contractName");
            string memory rawName;
            try vm.parseJsonString(json, nameKey) returns (string memory s) {
                rawName = s;
            } catch {
                break; // no more entries
            }
            string memory simple = _simpleContractName(rawName);
            if (keccak256(bytes(simple)) == desired) {
                string memory addrKey = string.concat(".transactions[", idx, "].contractAddress");
                try vm.parseJsonAddress(json, addrKey) returns (address deployed) {
                    if (deployed != address(0)) {
                        found = deployed; // keep last match
                    }
                } catch {}
            }
        }
        return found;
    }

    function _inferL1TokenFromBroadcast(uint256 l1ChainId) internal view returns (address) {
        return _inferFromBroadcast(l1ChainId, "1_DeployCNSTokenL1.s.sol", "ShoTokenL1");
    }

    function _inferL2ProxyFromBroadcast(uint256 l2ChainId) internal view returns (address) {
        return _inferFromBroadcast(l2ChainId, "2_DeployCNSTokenL2.s.sol", "ERC1967Proxy");
    }

    function _inferTimelockFromBroadcast(uint256 l2ChainId) internal view returns (address) {
        // Try from L2 deploy script first (may deploy timelock)
        address addr = _inferFromBroadcast(l2ChainId, "2_DeployCNSTokenL2.s.sol", "TimelockController");
        if (addr != address(0)) return addr;
        // Also try upgrade script in case timelock was deployed there earlier
        addr = _inferFromBroadcast(l2ChainId, "3_UpgradeCNSTokenL2ToV2.s.sol", "TimelockController");
        return addr;
    }

    // ============================================
    // L2 Address Resolution Helpers
    // ============================================

    /**
     * @notice Resolve L2 token proxy address from env, config, or broadcast artifacts
     * @param cfg EnvConfig containing proxy address
     * @return The resolved proxy address
     */
    function _resolveL2ProxyAddress(EnvConfig memory cfg) internal view returns (address) {
        address fromEnv = address(0);
        try vm.envAddress("CNS_TOKEN_L2_PROXY") returns (address a) {
            fromEnv = a;
        } catch {}
        if (fromEnv != address(0)) return fromEnv;

        if (cfg.l2.proxy != address(0)) {
            return cfg.l2.proxy;
        }

        address fromArtifacts = _inferL2ProxyFromBroadcast(block.chainid);
        return fromArtifacts;
    }

    /**
     * @notice Resolve L2 timelock address from env, config, or broadcast artifacts
     * @param cfg EnvConfig containing timelock address
     * @param proxyAddress The proxy address (used to avoid false matches)
     * @return The resolved timelock address, or 0x0 if not found
     */
    function _resolveL2TimelockAddress(EnvConfig memory cfg, address proxyAddress) internal view returns (address) {
        address timelockAddress = vm.envOr("CNS_L2_TIMELOCK", cfg.l2.timelock.addr);
        if (timelockAddress == address(0)) {
            address inferred = _inferTimelockFromBroadcast(block.chainid);
            if (inferred != address(0) && inferred != proxyAddress) {
                try TimelockController(payable(inferred)).getMinDelay() returns (uint256) {
                    timelockAddress = inferred;
                } catch {}
            }
        }
        return timelockAddress;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./BaseScript.sol";
import "../src/CNSTokenL1.sol";

/**
 * @title DeployCNSTokenL1
 * @notice Deploys CNS Token on L1 (Ethereum) with fixed supply
 * @dev This is a simple ERC20 with ERC20Permit, designed to be bridged to L2
 * 
 * Usage:
 *   # Sepolia testnet
 *   forge script script/1_DeployCNSTokenL1.s.sol:DeployCNSTokenL1 \
 *     --rpc-url sepolia \
 *     --broadcast \
 *     --verify
 * 
 *   # Mainnet
 *   forge script script/1_DeployCNSTokenL1.s.sol:DeployCNSTokenL1 \
 *     --rpc-url mainnet \
 *     --broadcast \
 *     --verify \
 *     --slow
 * 
 *   # Local testing
 *   forge script script/1_DeployCNSTokenL1.s.sol:DeployCNSTokenL1 \
 *     --rpc-url local \
 *     --broadcast
 * 
 * Environment Variables Required:
 *   - PRIVATE_KEY: Deployer private key
 *   - CNS_OWNER: Address that will receive initial token supply
 *   - MAINNET_DEPLOYMENT_ALLOWED: Set to true for mainnet deployments
 */
contract DeployCNSTokenL1 is BaseScript {
    // Token parameters
    string constant TOKEN_NAME = "Canonical CNS Token";
    string constant TOKEN_SYMBOL = "CNS";
    uint256 constant INITIAL_SUPPLY = 100_000_000 * 10 ** 18; // 100M tokens
    
    CNSTokenL1 public token;
    
    function run() external {
        // Get deployer credentials
        (uint256 deployerPrivateKey, address deployer) = _getDeployer();
        
        // Get and validate owner address
        address owner = vm.envAddress("CNS_OWNER");
        _requireNonZeroAddress(owner, "CNS_OWNER");
        
        // Log deployment info
        _logDeploymentHeader("Deploying CNS Token L1");
        console.log("Token Name:", TOKEN_NAME);
        console.log("Token Symbol:", TOKEN_SYMBOL);
        console.log("Initial Supply:", INITIAL_SUPPLY / 10 ** 18, "tokens");
        console.log("Supply Recipient (Owner):", owner);
        console.log("Deployer:", deployer);
        
        // Safety check for mainnet
        _requireMainnetConfirmation();
        
        // Deploy L1 token
        vm.startBroadcast(deployerPrivateKey);
        
        token = new CNSTokenL1(TOKEN_NAME, TOKEN_SYMBOL, INITIAL_SUPPLY, owner);
        
        vm.stopBroadcast();
        
        // Log deployment results
        _logDeploymentResults(owner);
        
        // Log verification command
        _logVerificationCommand(address(token), "src/CNSTokenL1.sol:CNSTokenL1");
    }
    
    function _logDeploymentResults(address owner) internal view {
        console.log("\n=== Deployment Complete ===");
        console.log("Network:", _getNetworkName(block.chainid));
        console.log("CNSTokenL1:", address(token));
        console.log("Owner Balance:", token.balanceOf(owner) / 10 ** 18, "tokens");
        console.log("Total Supply:", token.totalSupply() / 10 ** 18, "tokens");
        console.log("\n=== Token Info ===");
        console.log("Name:", token.name());
        console.log("Symbol:", token.symbol());
        console.log("Decimals:", token.decimals());
        
        // Log next steps
        console.log("\n=== Next Steps ===");
        console.log("1. Verify the contract (see command below)");
        console.log("2. Use this L1 token address when deploying L2 token");
        console.log("3. Bridge tokens using the Linea canonical bridge");
        console.log("   L1 Token Address:", address(token));
    }
}


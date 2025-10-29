// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./BaseScript.sol";
import "./ConfigLoader.sol";
import "../src/ShoTokenL1.sol";
import {StdStyle} from "forge-std/StdStyle.sol";

/**
 * @title DeployShoTokenL1
 * @notice Deploys SHO Token on L1 (Ethereum) with fixed supply
 * @dev This is a simple ERC20 with ERC20Permit, designed to be bridged to L2
 *
 * Usage:
 *   # Default (dev): infer config from ENV
 *   forge script script/1_DeployShoTokenL1.s.sol:DeployShoTokenL1 \
 *     --rpc-url sepolia \
 *     --broadcast \
 *     --verify
 *
 *   # Explicit non-default environment via ENV
 *   ENV=production forge script script/1_DeployShoTokenL1.s.sol:DeployShoTokenL1 \
 *     --rpc-url mainnet \
 *     --broadcast \
 *     --verify
 *
 *   # Config file path is fixed: config/<ENV>.json
 *
 * Environment Variables Required:
 *   - PRIVATE_KEY: Deployer private key (from your shell env)
 *   - ENV: Select public config JSON
 *   - MAINNET_DEPLOYMENT_ALLOWED: Set to true for mainnet deployments
 */
contract DeployShoTokenL1 is BaseScript {
    ShoTokenL1 public token;

    // Convenience no-arg entrypoint: infer config path
    function run() external {
        EnvConfig memory cfg = _loadEnvConfig();
        _runWithConfig(cfg);
    }

    function _runWithConfig(EnvConfig memory cfg) internal {
        // Load token parameters: env overrides take precedence, fall back to config
        string memory tokenName = vm.envOr("L1_TOKEN_NAME", cfg.l1.name);
        string memory tokenSymbol = vm.envOr("L1_TOKEN_SYMBOL", cfg.l1.symbol);
        uint256 initialSupply = vm.envOr("L1_INITIAL_SUPPLY", cfg.l1.initialSupply);

        // Get deployer credentials
        (uint256 deployerPrivateKey, address deployer) = _getDeployer();

        // Owner comes from config (admin field)
        address admin = cfg.l1.roles.admin;
        admin = vm.envOr("SHO_DEFAULT_ADMIN", admin);
        _requireNonZeroAddress(admin, "Admin");

        // Log deployment info
        _logDeploymentHeader("Deploying SHO Token L1");
        console.log("Token Name:", tokenName);
        console.log("Token Symbol:", tokenSymbol);
        console.log("Initial Supply:", initialSupply / 10 ** 18, "tokens");
        console.log("Supply Recipient (Owner):", admin);
        console.log("Deployer:", deployer);

        // Safety check for mainnet
        _requireMainnetConfirmation();

        // Deploy L1 token
        vm.startBroadcast(deployerPrivateKey);

        token = new ShoTokenL1(tokenName, tokenSymbol, initialSupply, admin);

        vm.stopBroadcast();

        // Log deployment results
        _logDeploymentResults(admin, tokenName, tokenSymbol);

        // Log verification command
        _logVerificationCommand(address(token), "src/ShoTokenL1.sol:ShoTokenL1");
    }

    function _logDeploymentResults(address owner, string memory tokenName, string memory tokenSymbol) internal view {
        console.log("\n=== Deployment Complete ===");
        console.log("Network:", _getNetworkName(block.chainid));
        console.log("ShoTokenL1:", address(token));
        console.log("Owner Balance:", token.balanceOf(owner) / 10 ** 18, "tokens");
        console.log("Total Supply:", token.totalSupply() / 10 ** 18, "tokens");
        console.log("\n=== Token Info ===");
        console.log("Name:", tokenName);
        console.log("Symbol:", tokenSymbol);
        console.log("Decimals:", token.decimals());

        // Log next steps
        console.log("\n=== Next Steps ===");
        console.log("1. Verify the contract (see command below)");
        console.log("2. Use this L1 token address when deploying L2 token");
        console.log("3. Bridge tokens using the Linea canonical bridge");
        console.log("   L1 Token Address:", address(token));

        // Final prominent contract address display
        console.log("\n");
        console.log(StdStyle.green("================================================================================"));
        console.log(StdStyle.yellow(StdStyle.bold(">>> DEPLOYED CONTRACT ADDRESS <<<")));
        console.log(StdStyle.cyan(StdStyle.bold(vm.toString(address(token)))));
        console.log(StdStyle.green("================================================================================"));
    }
}

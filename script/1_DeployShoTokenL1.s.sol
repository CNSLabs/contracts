// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./BaseScript.sol";
import "./ConfigLoader.sol";
import "../src/ShoTokenL1.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {StdStyle} from "forge-std/StdStyle.sol";

/**
 * @title DeployShoTokenL1
 * @notice Deploys SHO Token on L1 (Ethereum) as upgradeable UUPS contract
 * @dev This script deploys ShoTokenL1 with:
 *      - Role separation (defaultAdmin, upgrader via timelock, pauser, allowlist admin)
 *      - Pausability and allowlist controls
 *      - UUPS upgradeability
 *      - Automatic TimelockController deployment with UPGRADER_ROLE
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
 *
 * Optional Configuration (with defaults from config):
 *   - SHO_DEFAULT_ADMIN: Address for DEFAULT_ADMIN_ROLE
 *   - SHO_PAUSER: Emergency pause address
 *   - SHO_ALLOWLIST_ADMIN: Allowlist manager address
 *   - SHO_INITIAL_RECIPIENT: Receives initial 1B token supply
 *   - SHO_TIMELOCK_PROPOSER: Override timelock proposer address
 *   - L1_TOKEN_NAME: Token name
 *   - L1_TOKEN_SYMBOL: Token symbol
 *
 * Notes:
 *   - TimelockController is automatically deployed and granted UPGRADER_ROLE
 *   - All setup is atomic - single transaction with no intermediate steps
 *   - No private keys required for DEFAULT_ADMIN role (supports multisig)
 */
contract DeployShoTokenL1 is BaseScript {
    ShoTokenL1 public token;
    ERC1967Proxy public proxy;
    ShoTokenL1 public implementation;
    TimelockController public timelock;

    // Convenience no-arg entrypoint: infer config path
    function run() external {
        EnvConfig memory cfg = _loadEnvConfig();
        _runWithConfig(cfg);
    }

    function _runWithConfig(EnvConfig memory cfg) internal {
        // Load token parameters: env overrides take precedence, fall back to config
        string memory tokenName = vm.envOr("L1_TOKEN_NAME", cfg.l1.name);
        string memory tokenSymbol = vm.envOr("L1_TOKEN_SYMBOL", cfg.l1.symbol);

        // Get deployer credentials
        (uint256 deployerPrivateKey, address deployer) = _getDeployer();

        // Get roles from config with env overrides
        address defaultAdmin = vm.envOr("SHO_DEFAULT_ADMIN", cfg.l1.roles.admin);
        address pauser = vm.envOr("SHO_PAUSER", cfg.l1.roles.pauser);
        address allowlistAdmin = vm.envOr("SHO_ALLOWLIST_ADMIN", cfg.l1.roles.allowlistAdmin);
        address initialRecipient = vm.envOr("SHO_INITIAL_RECIPIENT", defaultAdmin);

        // Validate addresses
        _requireNonZeroAddress(defaultAdmin, "DefaultAdmin");
        _requireNonZeroAddress(pauser, "Pauser");
        _requireNonZeroAddress(allowlistAdmin, "AllowlistAdmin");
        _requireNonZeroAddress(initialRecipient, "InitialRecipient");

        // Log deployment info
        _logDeploymentHeader("Deploying SHO Token L1 (Upgradeable)");
        console.log("Token Name:", tokenName);
        console.log("Token Symbol:", tokenSymbol);
        console.log("Initial Supply:", 1_000_000_000, "tokens (1B)");
        console.log("Initial Recipient:", initialRecipient);
        console.log("Default Admin:", defaultAdmin);
        console.log("Pauser:", pauser);
        console.log("Allowlist Admin:", allowlistAdmin);
        console.log("Deployer:", deployer);

        // Safety check for mainnet
        _requireMainnetConfirmation();

        // Deploy TimelockController first
        console.log("\n=== Timelock Deployment ===");
        uint256 minDelay = cfg.l1.timelock.minDelay;
        address tlAdmin = cfg.l1.timelock.admin;
        address[] memory proposers = cfg.l1.timelock.proposers;
        address proposerOverride = vm.envOr("SHO_TIMELOCK_PROPOSER", address(0));
        if (proposerOverride != address(0)) {
            proposers = new address[](1);
            proposers[0] = proposerOverride;
        }
        address[] memory executors = cfg.l1.timelock.executors;

        require(minDelay > 0, "timelock minDelay=0");
        require(tlAdmin != address(0), "timelock admin=0");

        vm.startBroadcast(deployerPrivateKey);
        timelock = new TimelockController(minDelay, proposers, executors, tlAdmin);
        vm.stopBroadcast();
        console.log("Deployed TimelockController:", address(timelock));
        console.log("Min delay:", timelock.getMinDelay());

        // Deploy upgradeable token (implementation + proxy)
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy implementation
        console.log("\n1. Deploying ShoTokenL1 implementation...");
        implementation = new ShoTokenL1();
        console.log("   Implementation:", address(implementation));

        // 2. Prepare initialization data
        // If initialRecipient is different from defaultAdmin, add them to allowlist
        address[] memory initialAllowlist;
        if (initialRecipient != defaultAdmin) {
            initialAllowlist = new address[](1);
            initialAllowlist[0] = initialRecipient;
            console.log("   Note: initialRecipient differs from defaultAdmin, adding to allowlist");
        } else {
            initialAllowlist = new address[](0);
        }

        bytes memory initData = abi.encodeWithSelector(
            ShoTokenL1.initialize.selector,
            defaultAdmin,
            address(timelock),
            pauser,
            allowlistAdmin,
            initialRecipient,
            tokenName,
            tokenSymbol,
            initialAllowlist
        );

        // 3. Deploy proxy with initialization
        console.log("\n2. Deploying ERC1967 proxy...");
        proxy = new ERC1967Proxy(address(implementation), initData);
        token = ShoTokenL1(address(proxy));
        console.log("   Proxy:", address(proxy));

        // CRITICAL: Verify initialization happened successfully
        console.log("\n3. Verifying initialization...");
        require(
            token.hasRole(0x0000000000000000000000000000000000000000000000000000000000000000, defaultAdmin),
            "FATAL: Initialization failed - defaultAdmin doesn't have DEFAULT_ADMIN_ROLE"
        );
        require(
            token.hasRole(keccak256("UPGRADER_ROLE"), address(timelock)),
            "FATAL: Initialization failed - timelock doesn't have UPGRADER_ROLE"
        );
        require(
            token.hasRole(keccak256("PAUSER_ROLE"), pauser),
            "FATAL: Initialization failed - pauser doesn't have PAUSER_ROLE"
        );
        require(
            token.hasRole(keccak256("ALLOWLIST_ADMIN_ROLE"), allowlistAdmin),
            "FATAL: Initialization failed - allowlistAdmin doesn't have ALLOWLIST_ADMIN_ROLE"
        );
        console.log("   [OK] Contract initialized successfully");
        console.log("   [OK] All roles assigned correctly");
        console.log("   [OK] UPGRADER_ROLE granted to TimelockController");

        vm.stopBroadcast();

        // Log deployment results
        _logDeploymentResults(initialRecipient, tokenName, tokenSymbol);

        // Log verification commands
        console.log("\n=== Verification Commands ===");
        _logVerificationCommand(address(implementation), "src/ShoTokenL1.sol:ShoTokenL1");
        console.log("# Proxy verification (if needed):");
        console.log("# forge verify-contract", address(proxy), "ERC1967Proxy");
    }

    function _logDeploymentResults(address recipient, string memory tokenName, string memory tokenSymbol)
        internal
        view
    {
        console.log("\n=== Deployment Complete ===");
        console.log("Network:", _getNetworkName(block.chainid));
        console.log("Implementation:", address(implementation));
        console.log("Proxy (Token Address):", address(token));
        if (address(timelock) != address(0)) {
            console.log("Timelock:", address(timelock));
            console.log("MinDelay:", timelock.getMinDelay());
        }
        console.log("Recipient Balance:", token.balanceOf(recipient) / 10 ** 18, "tokens");
        console.log("Total Supply:", token.totalSupply() / 10 ** 18, "tokens");
        console.log("\n=== Token Info ===");
        console.log("Name:", tokenName);
        console.log("Symbol:", tokenSymbol);
        console.log("Decimals:", token.decimals());
        console.log("Allowlist Enabled:", token.senderAllowlistEnabled());

        console.log("\n=== Access Control (Role Separation) ===");
        console.log("Default Admin: Controls role management");
        console.log("Upgrader (via Timelock):", address(timelock));
        console.log("  - Controls: Contract upgrades");
        console.log("  - MinDelay:", timelock.getMinDelay(), "seconds");
        console.log("Pauser: Controls emergency pause/unpause");
        console.log("Allowlist Admin: Controls sender allowlist management");

        // Log next steps
        console.log("\n=== Next Steps ===");
        console.log("1. Verify the implementation contract (see command above)");
        console.log("2. Users interact with the proxy address (this is the token address)");
        console.log("3. To upgrade: deploy new implementation and schedule via timelock");
        console.log("   Proxy Address:", address(token));

        // Final prominent contract address display
        console.log("\n");
        console.log(StdStyle.green("================================================================================"));
        console.log(StdStyle.yellow(StdStyle.bold(">>> DEPLOYED CONTRACT ADDRESSES <<<")));
        console.log(StdStyle.green("================================================================================"));
        console.log(StdStyle.cyan(StdStyle.bold("Timelock Controller:")));
        console.log(StdStyle.cyan(vm.toString(address(timelock))));
        console.log("");
        console.log(StdStyle.magenta(StdStyle.bold("ShoTokenL1 Implementation:")));
        console.log(StdStyle.magenta(vm.toString(address(implementation))));
        console.log("");
        console.log(StdStyle.blue(StdStyle.bold("ShoTokenL1 Proxy (Main Contract):")));
        console.log(StdStyle.blue(vm.toString(address(proxy))));
        console.log(StdStyle.green("================================================================================"));
    }
}

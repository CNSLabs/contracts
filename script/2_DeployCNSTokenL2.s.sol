// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./BaseScript.sol";
import "./ConfigLoader.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import "../src/CNSTokenL2.sol";

/**
 * @title DeployCNSTokenL2
 * @notice Deploys CNS Token on L2 (Linea) as a bridged token with proxy pattern
 * @dev Deploys implementation + ERC1967 proxy with:
 *      - Bridge integration (Linea canonical bridge)
 *      - Pausability
 *      - Allowlist controls
 *      - UUPS upgradeability
 *
 * Usage:
 *   # Default (dev): infer config from ENV
 *   forge script script/2_DeployCNSTokenL2.s.sol:DeployCNSTokenL2 \
 *     --rpc-url linea_sepolia \
 *     --broadcast \
 *     --verify
 *
 *   # Explicit non-default environment via ENV
 *   ENV=production forge script script/2_DeployCNSTokenL2.s.sol:DeployCNSTokenL2 \
 *     --rpc-url linea \
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
contract DeployCNSTokenL2 is BaseScript {
    // Token parameters now loaded from config JSON
    string L2_NAME;
    string L2_SYMBOL;
    uint8 L2_DECIMALS;

    // Deployed contracts
    CNSTokenL2 public implementation;
    ERC1967Proxy public proxy;
    CNSTokenL2 public token;
    TimelockController public timelock;

    // Convenience no-arg entrypoint: infer config path
    function run() external {
        EnvConfig memory cfg = _loadEnvConfig();

        L2_NAME = cfg.l2.name;
        L2_SYMBOL = cfg.l2.symbol;
        L2_DECIMALS = uint8(cfg.l2.decimals);

        (uint256 deployerPrivateKey, address deployer) = _getDeployer();

        address owner = cfg.l2.roles.admin;
        address l1Token = cfg.l2.l1Token;
        if (l1Token == address(0)) {
            address inferred = _inferL1TokenFromBroadcast(cfg.l1.chain.chainId);
            if (inferred != address(0)) {
                console.log("[Info] Using L1 token from broadcast artifacts:", inferred);
                l1Token = inferred;
            }
        }
        address bridge = cfg.l2.bridge;

        _requireNonZeroAddress(owner, "CNS_OWNER");
        _requireNonZeroAddress(l1Token, "CNS_TOKEN_L1");
        _requireNonZeroAddress(bridge, "LINEA_L2_BRIDGE");

        _logDeploymentHeader("Deploying CNS Token L2");
        console.log("Token Name:", L2_NAME);
        console.log("Token Symbol:", L2_SYMBOL);
        console.log("Decimals:", L2_DECIMALS);
        console.log("Owner (Admin):", owner);
        console.log("L1 Token:", l1Token);
        console.log("Bridge:", bridge);
        console.log("Deployer:", deployer);

        console.log("\n=== Pre-Deployment Validation ===");
        require(owner != address(0), "FATAL: CNS_OWNER cannot be zero address");
        require(l1Token != address(0), "FATAL: CNS_TOKEN_L1 cannot be zero address");
        require(bridge != address(0), "FATAL: LINEA_L2_BRIDGE cannot be zero address");
        console.log("[OK] All required addresses are non-zero");

        _requireMainnetConfirmation();

        vm.startBroadcast(deployerPrivateKey);
        console.log("\n1. Deploying CNSTokenL2 implementation...");
        implementation = new CNSTokenL2();
        console.log("   Implementation:", address(implementation));

        bytes memory initCalldata = abi.encodeWithSelector(
            CNSTokenL2.initialize.selector, owner, bridge, l1Token, L2_NAME, L2_SYMBOL, L2_DECIMALS
        );

        console.log("\n2. Deploying ERC1967 proxy...");
        proxy = new ERC1967Proxy(address(implementation), initCalldata);
        token = CNSTokenL2(address(proxy));
        console.log("   Proxy:", address(proxy));

        console.log("\n3. Verifying initialization...");
        require(token.l1Token() == l1Token, "FATAL: Initialization failed - l1Token not set");
        require(token.bridge() == bridge, "FATAL: Initialization failed - bridge not set");
        require(
            token.hasRole(0x0000000000000000000000000000000000000000000000000000000000000000, owner),
            "FATAL: Initialization failed - owner doesn't have DEFAULT_ADMIN_ROLE"
        );
        require(
            token.hasRole(keccak256("UPGRADER_ROLE"), owner),
            "FATAL: Initialization failed - owner doesn't have UPGRADER_ROLE"
        );
        console.log("   [OK] Contract initialized successfully");
        console.log("   [OK] Owner has admin roles");

        vm.stopBroadcast();

        _verifyDeployment(owner, bridge, l1Token);

        // Deploy or attach to a TimelockController and assign UPGRADER_ROLE
        _setupTimelock(cfg, deployerPrivateKey, owner);

        _logDeploymentResults(owner, bridge, l1Token, initCalldata);
    }

    // Removed local inference: use BaseScript helpers

    function _verifyDeployment(address owner, address bridge, address l1Token) internal view {
        console.log("\n=== Running Additional Deployment Checks ===");

        // Check proxy points to implementation
        bytes32 implementationSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        address proxyImpl = address(uint160(uint256(vm.load(address(proxy), implementationSlot))));
        require(proxyImpl == address(implementation), "Proxy implementation mismatch");
        console.log("[OK] Proxy points to correct implementation");

        // Check token initialization
        require(keccak256(bytes(token.name())) == keccak256(bytes(L2_NAME)), "Name mismatch");
        require(keccak256(bytes(token.symbol())) == keccak256(bytes(L2_SYMBOL)), "Symbol mismatch");
        require(token.decimals() == L2_DECIMALS, "Decimals mismatch");
        require(token.bridge() == bridge, "Bridge mismatch");
        require(token.l1Token() == l1Token, "L1 token mismatch");
        console.log("[OK] Token initialized correctly");

        // Check roles
        bytes32 DEFAULT_ADMIN_ROLE = 0x00;
        bytes32 PAUSER_ROLE = keccak256("PAUSER_ROLE");
        bytes32 ALLOWLIST_ADMIN_ROLE = keccak256("ALLOWLIST_ADMIN_ROLE");
        bytes32 UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

        require(token.hasRole(DEFAULT_ADMIN_ROLE, owner), "Owner missing DEFAULT_ADMIN_ROLE");
        require(token.hasRole(PAUSER_ROLE, owner), "Owner missing PAUSER_ROLE");
        require(token.hasRole(ALLOWLIST_ADMIN_ROLE, owner), "Owner missing ALLOWLIST_ADMIN_ROLE");
        require(token.hasRole(UPGRADER_ROLE, owner), "Owner missing UPGRADER_ROLE");
        console.log("[OK] Owner has all required roles");

        // Check sender allowlist
        require(token.isSenderAllowlisted(address(token)), "Token not allowlisted");
        require(token.isSenderAllowlisted(bridge), "Bridge not allowlisted");
        require(token.isSenderAllowlisted(owner), "Owner not allowlisted");
        require(token.senderAllowlistEnabled(), "Sender allowlist not enabled");
        console.log("[OK] Default addresses allowlisted");

        console.log("\n[SUCCESS] All deployment checks passed!");
    }

    function _setupTimelock(EnvConfig memory cfg, uint256 deployerPrivateKey, address owner) internal {
        uint256 minDelay = cfg.l2.timelock.minDelay;
        address tlAdmin = cfg.l2.timelock.admin;
        address[] memory proposers = cfg.l2.timelock.proposers;
        address[] memory executors = cfg.l2.timelock.executors;

        console.log("\n=== Timelock Setup ===");
        require(minDelay > 0, "timelock minDelay=0");
        require(tlAdmin != address(0), "timelock admin=0");

        vm.startBroadcast(deployerPrivateKey);
        timelock = new TimelockController(minDelay, proposers, executors, tlAdmin);
        vm.stopBroadcast();
        console.log("Deployed TimelockController:", address(timelock));
        console.log("Min delay:", timelock.getMinDelay());

        // Assign roles using the owner (DEFAULT_ADMIN_ROLE) key
        bytes32 UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
        bytes32 DEFAULT_ADMIN_ROLE = 0x00;

        uint256 adminPrivateKey = vm.envUint("CNS_OWNER_PRIVATE_KEY");
        address adminActor = vm.addr(adminPrivateKey);
        require(adminActor == owner, "CNS_OWNER_PRIVATE_KEY != owner");
        require(token.hasRole(DEFAULT_ADMIN_ROLE, adminActor), "owner lacks DEFAULT_ADMIN_ROLE");

        vm.startBroadcast(adminPrivateKey);
        token.grantRole(UPGRADER_ROLE, address(timelock));
        token.revokeRole(UPGRADER_ROLE, owner);
        vm.stopBroadcast();
        console.log("Granted UPGRADER_ROLE to TimelockController");
        console.log("Revoked UPGRADER_ROLE from owner");
    }

    function _logDeploymentResults(address owner, address bridge, address l1Token, bytes memory initCalldata)
        internal
        view
    {
        console.log("\n=== Deployment Complete ===");
        console.log("Network:", _getNetworkName(block.chainid));
        console.log("Implementation:", address(implementation));
        console.log("Proxy (Token):", address(token));
        if (address(timelock) != address(0)) {
            console.log("Timelock:", address(timelock));
            console.log("MinDelay:", timelock.getMinDelay());
        }

        console.log("\n=== Token Configuration ===");
        console.log("Name:", token.name());
        console.log("Symbol:", token.symbol());
        console.log("Decimals:", token.decimals());
        console.log("L1 Token:", l1Token);
        console.log("Bridge:", bridge);
        console.log("Paused:", token.paused());

        console.log("\n=== Access Control ===");
        console.log("Owner (has all roles):", owner);
        console.log("Sender Allowlist Enabled:", token.senderAllowlistEnabled());
        console.log("Sender Allowlisted:");
        console.log("  - Token contract:", token.isSenderAllowlisted(address(token)));
        console.log("  - Bridge:", token.isSenderAllowlisted(bridge));
        console.log("  - Owner:", token.isSenderAllowlisted(owner));

        // Log verification commands
        _logVerificationCommands(initCalldata);

        // Log next steps
        console.log("\n=== Next Steps ===");
        console.log("1. Verify contracts (see commands below)");
        console.log("2. Add addresses to sender allowlist: token.setSenderAllowed(address, true)");
        console.log("3. Optionally disable allowlist: token.setSenderAllowlistEnabled(false)");
        console.log("4. Bridge tokens from L1 using Linea bridge");
        console.log("5. Test transfers between allowlisted addresses");
        console.log("6. For upgrades, use 3_UpgradeCNSTokenL2ToV2.s.sol");
    }

    function _logVerificationCommands(bytes memory initCalldata) internal view {
        console.log("\n=== Verification Commands ===");

        // Implementation verification
        console.log("\n1. Verify implementation:");
        _logVerificationCommand(address(implementation), "src/CNSTokenL2.sol:CNSTokenL2");

        // Proxy verification
        console.log("\n2. Verify proxy:");
        string memory chainParam = _getChainParam(block.chainid);
        if (bytes(chainParam).length > 0) {
            console.log("To verify the proxy:");
            console.log(
                string.concat(
                    "forge verify-contract ",
                    vm.toString(address(proxy)),
                    " lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy ",
                    chainParam,
                    " --constructor-args ",
                    vm.toString(abi.encode(address(implementation), initCalldata)),
                    " --watch"
                )
            );
        }
    }
}

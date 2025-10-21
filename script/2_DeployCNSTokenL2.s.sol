// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./BaseScript.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import "../src/CNSTokenL2.sol";

/**
 * @title DeployCNSTokenL2
 * @notice Deploys CNS Token on L2 (Linea) as a bridged token with role separation
 * @dev This script deploys CNSTokenL2 with:
 *      - Role separation (defaultAdmin, upgrader, pauser, allowlist admin)
 *      - Bridge integration (Linea canonical bridge)
 *      - Pausability and allowlist controls
 *      - UUPS upgradeability
 *      - Atomic initialization for security
 *
 * Usage:
 *   # Linea Sepolia testnet
 *   forge script script/2_DeployCNSTokenL2.s.sol:DeployCNSTokenL2 \
 *     --rpc-url linea_sepolia \
 *     --broadcast \
 *     --verify
 *
 *   # Linea Mainnet
 *   forge script script/2_DeployCNSTokenL2.s.sol:DeployCNSTokenL2 \
 *     --rpc-url linea \
 *     --broadcast \
 *     --verify \
 *     --slow
 *
 *   # Local testing
 *   forge script script/2_DeployCNSTokenL2.s.sol:DeployCNSTokenL2 \
 *     --rpc-url local \
 *     --broadcast
 *
 * Environment Variables Required:
 *   - PRIVATE_KEY: Deployer private key (secret)
 *   - CNS_DEFAULT_ADMIN: Address for DEFAULT_ADMIN_ROLE (governance address)
 *   - CNS_TOKEN_L1: L1 canonical token address
 *   - LINEA_L2_BRIDGE: Linea L2 bridge contract address
 *   - MAINNET_DEPLOYMENT_ALLOWED: Set to true for mainnet deployments
 *
 * Optional Configuration (with defaults):
 *   - L2_TOKEN_NAME: Token name (default: "CNS Linea Token")
 *   - L2_TOKEN_SYMBOL: Token symbol (default: "CNSL")
 *   - L2_TOKEN_DECIMALS: Token decimals (default: 18)
 *   - CNS_UPGRADER: Contract upgrader address (defaults to CNS_DEFAULT_ADMIN)
 *   - CNS_PAUSER: Emergency pause address (defaults to CNS_DEFAULT_ADMIN)
 *   - CNS_ALLOWLIST_ADMIN: Allowlist manager address (defaults to CNS_DEFAULT_ADMIN)
 *
 * Bridge Addresses:
 *   Linea Sepolia: 0x93DcAdf238932e6e6a85852caC89cBd71798F463
 *   Linea Mainnet: 0xd19d4B5d358258f05D7B411E21A1460D11B0876F
 */
contract DeployCNSTokenL2 is BaseScript {
    // Token configuration defaults (can be overridden via environment)
    string constant DEFAULT_L2_NAME = "CNS Linea Token";
    string constant DEFAULT_L2_SYMBOL = "CNSL";
    uint8 constant DEFAULT_L2_DECIMALS = 18;

    // Configuration with environment overrides
    string L2_NAME = vm.envOr("L2_TOKEN_NAME", DEFAULT_L2_NAME);
    string L2_SYMBOL = vm.envOr("L2_TOKEN_SYMBOL", DEFAULT_L2_SYMBOL);
    uint8 L2_DECIMALS = uint8(vm.envOr("L2_TOKEN_DECIMALS", uint256(DEFAULT_L2_DECIMALS)));

    // Deployed contracts
    CNSTokenL2 public implementation;
    ERC1967Proxy public proxy;
    CNSTokenL2 public token;
    TimelockController public timelock;

    function run() external {
        EnvConfig memory cfg = _loadEnvConfig();
        // Get deployer credentials
        (uint256 deployerPrivateKey, address deployer) = _getDeployer();

        // Get and validate required addresses
        address defaultAdmin = vm.envAddress("CNS_DEFAULT_ADMIN");
        address upgrader = vm.envOr("CNS_UPGRADER", defaultAdmin); // Defaults to defaultAdmin if not set
        address pauser = vm.envOr("CNS_PAUSER", defaultAdmin); // Defaults to defaultAdmin if not set
        address allowlistAdmin = vm.envOr("CNS_ALLOWLIST_ADMIN", defaultAdmin); // Defaults to defaultAdmin if not set

        _requireNonZeroAddress(defaultAdmin, "CNS_DEFAULT_ADMIN");
        _requireNonZeroAddress(upgrader, "CNS_UPGRADER");
        _requireNonZeroAddress(pauser, "CNS_PAUSER");
        _requireNonZeroAddress(allowlistAdmin, "CNS_ALLOWLIST_ADMIN");

        // Load Hedgey addresses from config
        address hedgeyBatchPlanner = cfg.hedgey.batchPlanner;
        address hedgeyTokenVestingPlans = cfg.hedgey.tokenVestingPlans;

        address l1Token = cfg.l2.l1Token;
        if (l1Token == address(0)) {
            address inferred = _inferL1TokenFromBroadcast(cfg.l1.chain.chainId);
            if (inferred != address(0)) {
                console.log("[Info] Using L1 token from broadcast artifacts:", inferred);
                l1Token = inferred;
            }
        }
        l1Token = vm.envOr("CNS_TOKEN_L1", l1Token);
        address bridge = vm.envOr("LINEA_L2_BRIDGE", cfg.l2.bridge);

        _requireNonZeroAddress(l1Token, "CNS_TOKEN_L1");
        _requireNonZeroAddress(bridge, "LINEA_L2_BRIDGE");

        // Log deployment info
        _logDeploymentHeader("Deploying CNS Token L2 with Role Separation");
        console.log("Token Name:", L2_NAME);
        console.log("Token Symbol:", L2_SYMBOL);
        console.log("Decimals:", L2_DECIMALS);
        console.log("\n=== Role Assignment ===");
        console.log("Default Admin:", defaultAdmin);
        console.log("Upgrader:", upgrader);
        console.log("Pauser:", pauser);
        console.log("Allowlist Admin:", allowlistAdmin);
        console.log("\n=== Contract Addresses ===");
        console.log("L1 Token:", l1Token);
        console.log("Bridge:", bridge);
        console.log("Deployer:", deployer);
        console.log("Hedgey Batch Planner:", hedgeyBatchPlanner);
        console.log("Hedgey Token Vesting Plans:", hedgeyTokenVestingPlans);

        // Pre-deployment validation
        console.log("\n=== Pre-Deployment Validation ===");
        require(defaultAdmin != address(0), "FATAL: CNS_DEFAULT_ADMIN cannot be zero address");
        require(upgrader != address(0), "FATAL: CNS_UPGRADER cannot be zero address");
        require(pauser != address(0), "FATAL: CNS_PAUSER cannot be zero address");
        require(allowlistAdmin != address(0), "FATAL: CNS_ALLOWLIST_ADMIN cannot be zero address");
        require(l1Token != address(0), "FATAL: CNS_TOKEN_L1 cannot be zero address");
        require(bridge != address(0), "FATAL: LINEA_L2_BRIDGE cannot be zero address");

        // Validate Hedgey addresses - required
        require(hedgeyBatchPlanner != address(0), "FATAL: HEDGEY_BATCH_PLANNER must be set");
        require(hedgeyBatchPlanner.code.length > 0, "FATAL: HEDGEY_BATCH_PLANNER is not a contract");
        console.log("[OK] Hedgey Batch Planner is a valid contract");

        require(hedgeyTokenVestingPlans != address(0), "FATAL: HEDGEY_TOKEN_VESTING_PLANS must be set");
        require(hedgeyTokenVestingPlans.code.length > 0, "FATAL: HEDGEY_TOKEN_VESTING_PLANS is not a contract");
        console.log("[OK] Hedgey Token Vesting Plans is a valid contract");

        console.log("[OK] All required addresses are non-zero");
        console.log("[INFO] Default Admin will also have backup access to operational roles");

        // Safety check for mainnet
        _requireMainnetConfirmation();

        // Deploy L2 token (implementation + proxy)
        vm.startBroadcast(deployerPrivateKey);

        console.log("\n1. Deploying CNSTokenL2 implementation...");
        implementation = new CNSTokenL2();
        console.log("   Implementation:", address(implementation));

        // Prepare initialization data
        bytes memory initCalldata = abi.encodeWithSelector(
            CNSTokenL2.initialize.selector,
            defaultAdmin,
            upgrader,
            pauser,
            allowlistAdmin,
            bridge,
            l1Token,
            L2_NAME,
            L2_SYMBOL,
            L2_DECIMALS
        );

        console.log("\n2. Deploying ERC1967 proxy...");
        proxy = new ERC1967Proxy(address(implementation), initCalldata);
        token = CNSTokenL2(address(proxy));
        console.log("   Proxy:", address(proxy));

        // CRITICAL: Verify initialization happened successfully
        console.log("\n3. Verifying initialization...");
        require(token.l1Token() == l1Token, "FATAL: Initialization failed - l1Token not set");
        require(token.bridge() == bridge, "FATAL: Initialization failed - bridge not set");
        require(
            token.hasRole(0x0000000000000000000000000000000000000000000000000000000000000000, defaultAdmin),
            "FATAL: Initialization failed - defaultAdmin doesn't have DEFAULT_ADMIN_ROLE"
        );
        require(
            token.hasRole(keccak256("UPGRADER_ROLE"), upgrader),
            "FATAL: Initialization failed - upgrader doesn't have UPGRADER_ROLE"
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

        vm.stopBroadcast();

        // Setup allowlist using owner's private key
        _setupAllowlist(hedgeyBatchPlanner, hedgeyTokenVestingPlans, defaultAdmin);
        // Verify deployment
        _verifyDeployment(
            defaultAdmin, upgrader, pauser, allowlistAdmin, bridge, l1Token, hedgeyBatchPlanner, hedgeyTokenVestingPlans
        );

        // Deploy or attach to a TimelockController and assign UPGRADER_ROLE
        _setupTimelock(cfg, deployerPrivateKey, upgrader);

        _logDeploymentResults(
            defaultAdmin,
            upgrader,
            pauser,
            allowlistAdmin,
            bridge,
            l1Token,
            hedgeyBatchPlanner,
            hedgeyTokenVestingPlans,
            initCalldata
        );
    }

    function _verifyDeployment(
        address defaultAdmin,
        address upgrader,
        address pauser,
        address allowlistAdmin,
        address bridge,
        address l1Token,
        address hedgeyBatchPlanner,
        address hedgeyTokenVestingPlans
    ) internal view {
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

        // Verify critical roles
        require(token.hasRole(DEFAULT_ADMIN_ROLE, defaultAdmin), "DefaultAdmin missing DEFAULT_ADMIN_ROLE");
        require(token.hasRole(UPGRADER_ROLE, upgrader), "Upgrader missing UPGRADER_ROLE");
        console.log("[OK] Critical roles assigned (DEFAULT_ADMIN + UPGRADER)");

        // Verify operational roles
        require(token.hasRole(PAUSER_ROLE, pauser), "Pauser missing PAUSER_ROLE");
        require(token.hasRole(ALLOWLIST_ADMIN_ROLE, allowlistAdmin), "AllowlistAdmin missing ALLOWLIST_ADMIN_ROLE");
        console.log("[OK] Operational roles assigned correctly");

        // Verify defaultAdmin has backup access to operational roles
        require(token.hasRole(PAUSER_ROLE, defaultAdmin), "DefaultAdmin missing backup PAUSER_ROLE");
        require(token.hasRole(ALLOWLIST_ADMIN_ROLE, defaultAdmin), "DefaultAdmin missing backup ALLOWLIST_ADMIN_ROLE");
        console.log("[OK] Default Admin has backup access to operational roles");

        // Check sender allowlist
        require(token.isSenderAllowlisted(address(token)), "Token not allowlisted");
        require(token.isSenderAllowlisted(bridge), "Bridge not allowlisted");
        require(token.isSenderAllowlisted(defaultAdmin), "DefaultAdmin not allowlisted");
        require(token.senderAllowlistEnabled(), "Sender allowlist not enabled");
        console.log("[OK] Default addresses allowlisted");

        // Check Hedgey addresses (required)
        require(token.isSenderAllowlisted(hedgeyBatchPlanner), "Hedgey Batch Planner not allowlisted");
        console.log("[OK] Hedgey Batch Planner allowlisted");

        require(token.isSenderAllowlisted(hedgeyTokenVestingPlans), "Hedgey Token Vesting Plans not allowlisted");
        console.log("[OK] Hedgey Token Vesting Plans allowlisted");

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

    function _setupAllowlist(address hedgeyBatchPlanner, address hedgeyTokenVestingPlans, address owner) internal {
        console.log("\n=== Allowlist Setup ===");

        // Get owner's private key for allowlist operations
        bytes32 DEFAULT_ADMIN_ROLE = 0x00;

        uint256 adminPrivateKey = vm.envUint("CNS_OWNER_PRIVATE_KEY");
        address adminActor = vm.addr(adminPrivateKey);
        require(adminActor == owner, "CNS_OWNER_PRIVATE_KEY != owner");
        require(token.hasRole(DEFAULT_ADMIN_ROLE, adminActor), "owner lacks DEFAULT_ADMIN_ROLE");

        console.log("Adding Hedgey addresses to allowlist...");
        address[] memory hedgeyAddresses = new address[](2);
        hedgeyAddresses[0] = hedgeyBatchPlanner;
        hedgeyAddresses[1] = hedgeyTokenVestingPlans;

        vm.startBroadcast(adminPrivateKey);
        token.setSenderAllowedBatch(hedgeyAddresses, true);
        vm.stopBroadcast();

        console.log("   [OK] Hedgey Batch Planner allowlisted:", hedgeyBatchPlanner);
        console.log("   [OK] Hedgey Token Vesting Plans allowlisted:", hedgeyTokenVestingPlans);
    }

    function _logDeploymentResults(
        address defaultAdmin,
        address upgrader,
        address pauser,
        address allowlistAdmin,
        address bridge,
        address l1Token,
        address hedgeyBatchPlanner,
        address hedgeyTokenVestingPlans,
        bytes memory initCalldata
    ) internal view {
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

        console.log("\n=== Access Control (Role Separation) ===");
        console.log("Default Admin:", defaultAdmin);
        console.log("  - Controls: Role management");
        console.log("  - Backup for: Pause/Unpause, Allowlist management");
        console.log("Upgrader:", upgrader);
        console.log("  - Controls: Contract upgrades");
        console.log("Pauser:", pauser);
        console.log("  - Controls: Emergency pause/unpause");
        console.log("Allowlist Admin:", allowlistAdmin);
        console.log("  - Controls: Sender allowlist management");
        console.log("\nSender Allowlist Enabled:", token.senderAllowlistEnabled());
        console.log("Sender Allowlisted:");
        console.log("  - Token contract:", token.isSenderAllowlisted(address(token)));
        console.log("  - Bridge:", token.isSenderAllowlisted(bridge));
        console.log("  - Default Admin:", token.isSenderAllowlisted(defaultAdmin));
        console.log("  - Hedgey Batch Planner:", token.isSenderAllowlisted(hedgeyBatchPlanner));
        console.log("  - Hedgey Token Vesting Plans:", token.isSenderAllowlisted(hedgeyTokenVestingPlans));

        // Log verification commands
        _logVerificationCommands(initCalldata);

        // Log next steps
        console.log("\n=== Next Steps ===");
        console.log("1. Verify contracts (see commands below)");
        console.log("2. Add additional addresses to sender allowlist: token.setSenderAllowed(address, true)");
        console.log("3. Optionally disable allowlist: token.setSenderAllowlistEnabled(false)");
        console.log("4. Bridge tokens from L1 using Linea bridge");
        console.log("5. Test transfers between allowlisted addresses");
        console.log("6. Test Hedgey integration with allowlisted addresses");
        console.log("7. For upgrades, use 3_UpgradeCNSTokenL2ToV2.s.sol");
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

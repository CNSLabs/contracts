// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./BaseScript.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
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
 *   - PRIVATE_KEY: Deployer private key
 *   - CNS_OWNER: Address that will have admin roles
 *   - CNS_TOKEN_L1: Address of the L1 token (deployed first)
 *   - LINEA_L2_BRIDGE: Linea L2 bridge address
 *   - MAINNET_DEPLOYMENT_ALLOWED: Set to true for mainnet deployments
 *
 * Bridge Addresses:
 *   Linea Sepolia: 0x93DcAdf238932e6e6a85852caC89cBd71798F463
 *   Linea Mainnet: 0xd19d4B5d358258f05D7B411E21A1460D11B0876F
 */
contract DeployCNSTokenL2 is BaseScript {
    // Token parameters
    string constant L2_NAME = "CNS Linea Token";
    string constant L2_SYMBOL = "CNSL";
    uint8 constant L2_DECIMALS = 18;

    // Deployed contracts
    CNSTokenL2 public implementation;
    ERC1967Proxy public proxy;
    CNSTokenL2 public token;

    function run() external {
        // Get deployer credentials
        (uint256 deployerPrivateKey, address deployer) = _getDeployer();

        // Get and validate required addresses
        address owner = vm.envAddress("CNS_OWNER");
        address l1Token = vm.envAddress("CNS_TOKEN_L1");
        address bridge = vm.envAddress("LINEA_L2_BRIDGE");

        _requireNonZeroAddress(owner, "CNS_OWNER");
        _requireNonZeroAddress(l1Token, "CNS_TOKEN_L1");
        _requireNonZeroAddress(bridge, "LINEA_L2_BRIDGE");

        // Log deployment info
        _logDeploymentHeader("Deploying CNS Token L2");
        console.log("Token Name:", L2_NAME);
        console.log("Token Symbol:", L2_SYMBOL);
        console.log("Decimals:", L2_DECIMALS);
        console.log("Owner (Admin):", owner);
        console.log("L1 Token:", l1Token);
        console.log("Bridge:", bridge);
        console.log("Deployer:", deployer);

        // Safety check for mainnet
        _requireMainnetConfirmation();

        // Deploy L2 token (implementation + proxy)
        vm.startBroadcast(deployerPrivateKey);

        console.log("\n1. Deploying CNSTokenL2 implementation...");
        implementation = new CNSTokenL2();
        console.log("   Implementation:", address(implementation));

        // Prepare initialization data
        bytes memory initCalldata = abi.encodeWithSelector(
            CNSTokenL2.initialize.selector, owner, bridge, l1Token, L2_NAME, L2_SYMBOL, L2_DECIMALS
        );

        console.log("\n2. Deploying ERC1967 proxy...");
        proxy = new ERC1967Proxy(address(implementation), initCalldata);
        token = CNSTokenL2(address(proxy));
        console.log("   Proxy:", address(proxy));

        vm.stopBroadcast();

        // Verify deployment
        _verifyDeployment(owner, bridge, l1Token);

        // Log deployment results
        _logDeploymentResults(owner, bridge, l1Token, initCalldata);
    }

    function _verifyDeployment(address owner, address bridge, address l1Token) internal view {
        console.log("\n=== Verifying Deployment ===");

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

        // Check allowlist
        require(token.isAllowlisted(address(token)), "Token not allowlisted");
        require(token.isAllowlisted(bridge), "Bridge not allowlisted");
        require(token.isAllowlisted(owner), "Owner not allowlisted");
        console.log("[OK] Default addresses allowlisted");

        console.log("\n[SUCCESS] All deployment checks passed!");
    }

    function _logDeploymentResults(address owner, address bridge, address l1Token, bytes memory initCalldata)
        internal
        view
    {
        console.log("\n=== Deployment Complete ===");
        console.log("Network:", _getNetworkName(block.chainid));
        console.log("Implementation:", address(implementation));
        console.log("Proxy (Token):", address(token));

        console.log("\n=== Token Configuration ===");
        console.log("Name:", token.name());
        console.log("Symbol:", token.symbol());
        console.log("Decimals:", token.decimals());
        console.log("L1 Token:", l1Token);
        console.log("Bridge:", bridge);
        console.log("Paused:", token.paused());

        console.log("\n=== Access Control ===");
        console.log("Owner (has all roles):", owner);
        console.log("Allowlisted:");
        console.log("  - Token contract:", token.isAllowlisted(address(token)));
        console.log("  - Bridge:", token.isAllowlisted(bridge));
        console.log("  - Owner:", token.isAllowlisted(owner));

        // Log verification commands
        _logVerificationCommands(initCalldata);

        // Log next steps
        console.log("\n=== Next Steps ===");
        console.log("1. Verify contracts (see commands below)");
        console.log("2. Add addresses to allowlist: token.setAllowlist(address, true)");
        console.log("3. Bridge tokens from L1 using Linea bridge");
        console.log("4. Test transfers between allowlisted addresses");
        console.log("5. For upgrades, use 3_UpgradeCNSTokenL2ToV2.s.sol");
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

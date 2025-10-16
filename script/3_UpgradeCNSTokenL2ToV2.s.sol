// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./BaseScript.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../src/CNSTokenL2.sol";
import "../src/CNSTokenL2V2.sol";

/**
 * @title UpgradeCNSTokenL2ToV2
 * @dev Script to upgrade CNSTokenL2 proxy from V1 to V2 (adds voting capabilities)
 * @notice This script:
 *         1. Deploys the new CNSTokenL2V2 implementation
 *         2. Upgrades the proxy to point to the new implementation
 *         3. Initializes V2-specific features (ERC20Votes)
 *
 * Environment Variables:
 *   - PRIVATE_KEY or CNS_OWNER_PRIVATE_KEY: Upgrader key (must have UPGRADER_ROLE)
 *   - ENV: Select public config JSON (optional if using artifact inference)
 *   - CNS_TOKEN_L2_PROXY: Optional override for proxy (else use config l2.proxy or broadcast inference)
 *   - MAINNET_DEPLOYMENT_ALLOWED: Set to true for mainnet deployments
 *
 * Usage:
 *   # Default (dev)
 *   forge script script/3_UpgradeCNSTokenL2ToV2.s.sol:UpgradeCNSTokenL2ToV2 \
 *     --rpc-url linea_sepolia \
 *     --broadcast
 *
 *   # Explicit non-default environment via ENV
 *   ENV=production forge script script/3_UpgradeCNSTokenL2ToV2.s.sol:UpgradeCNSTokenL2ToV2 \
 *     --rpc-url linea \
 *     --broadcast
 *
 * Proxy resolution:
 *   - If CNS_TOKEN_L2_PROXY is not set, this script will try to infer it from
 *     broadcast/2_DeployCNSTokenL2.s.sol/<chainId>/run-latest.json by selecting
 *     the ERC1967Proxy address from the last deployment run on the current chain.
 */
contract UpgradeCNSTokenL2ToV2 is BaseScript {
    address public proxyAddress;
    address public newImplementation;

    function run() external {
        // Optionally load env config to allow proxy resolution via config
        EnvConfig memory cfg = _loadEnvConfig();
        // Try to get CNS_OWNER_PRIVATE_KEY first, fall back to PRIVATE_KEY
        uint256 ownerPrivateKey;
        address owner;

        try vm.envUint("CNS_OWNER_PRIVATE_KEY") returns (uint256 key) {
            ownerPrivateKey = key;
            owner = vm.addr(ownerPrivateKey);
            console.log("Using CNS_OWNER_PRIVATE_KEY");
        } catch {
            console.log("CNS_OWNER_PRIVATE_KEY not found, using PRIVATE_KEY");
            (ownerPrivateKey, owner) = _getDeployer();
        }

        // Resolve the proxy address from (priority): env var -> config -> broadcast
        proxyAddress = _resolveProxyAddress(cfg);
        _requireNonZeroAddress(proxyAddress, "CNS_TOKEN_L2_PROXY (resolved)");
        _requireContract(proxyAddress, "CNS_TOKEN_L2_PROXY (resolved)");

        // Log deployment info
        _logDeploymentHeader("Upgrading CNSTokenL2 to V2");
        console.log("Proxy address:", proxyAddress);
        console.log("Upgrader address:", owner);

        // Safety check for mainnet
        _requireMainnetConfirmation();

        // Check if owner has UPGRADER_ROLE before attempting upgrade
        CNSTokenL2 proxyV1 = CNSTokenL2(proxyAddress);
        bytes32 UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

        if (!proxyV1.hasRole(UPGRADER_ROLE, owner)) {
            console.log("\n[ERROR] Account does not have UPGRADER_ROLE!");
            console.log("Required role:", vm.toString(UPGRADER_ROLE));
            console.log("Your address:", owner);
            console.log("\nTo fix this:");
            console.log("1. Set CNS_OWNER_PRIVATE_KEY env var with the private key that has UPGRADER_ROLE");
            console.log("2. Or grant UPGRADER_ROLE to your current account first");
            revert("Missing UPGRADER_ROLE");
        }

        console.log("[OK] Account has UPGRADER_ROLE");

        vm.startBroadcast(ownerPrivateKey);

        // 1. Deploy new V2 implementation
        console.log("\n1. Deploying CNSTokenL2V2 implementation...");
        CNSTokenL2V2 implementationV2 = new CNSTokenL2V2();
        newImplementation = address(implementationV2);
        console.log("CNSTokenL2V2 implementation deployed at:", newImplementation);

        // 2. Prepare the initialization data for V2
        bytes memory initData = abi.encodeWithSelector(CNSTokenL2V2.initializeV2.selector);

        // 3. Perform the upgrade (calls upgradeToAndCall on the proxy)
        console.log("\n2. Upgrading proxy to V2 implementation...");
        CNSTokenL2V2 proxy = CNSTokenL2V2(proxyAddress);
        proxy.upgradeToAndCall(newImplementation, initData);
        console.log("Upgrade successful!");

        vm.stopBroadcast();

        // Verify the upgrade
        _verifyUpgrade();

        // Log summary
        _logUpgradeSummary();
    }

    function _verifyUpgrade() internal view {
        console.log("\n=== Verifying Upgrade ===");

        CNSTokenL2V2 proxy = CNSTokenL2V2(proxyAddress);

        // Get implementation address via EIP-1967 storage slot
        bytes32 implementationSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        address implementationAddress = address(uint160(uint256(vm.load(proxyAddress, implementationSlot))));

        console.log("Current implementation:", implementationAddress);
        console.log("Expected implementation:", newImplementation);

        require(implementationAddress == newImplementation, "Implementation not updated!");
        console.log("[SUCCESS] Implementation successfully updated");

        // Verify V2 functions are accessible
        console.log("\n[SUCCESS] Verifying V2 functionality:");
        console.log("  - Token name:", proxy.name());
        console.log("  - Token symbol:", proxy.symbol());
        console.log("  - Clock mode:", proxy.clock());
        console.log("  - CLOCK_MODE:", proxy.CLOCK_MODE());
        console.log("\n[SUCCESS] V2 voting functions are accessible!");
    }

    function _logUpgradeSummary() internal view {
        console.log("\n=== Upgrade Summary ===");
        console.log("Network:", _getNetworkName(block.chainid));
        console.log("Proxy address:", proxyAddress);
        console.log("New implementation (V2):", newImplementation);
        console.log("\n=== New Features in V2 ===");
        console.log("- ERC20Votes: delegation and voting power tracking");
        console.log("- delegate(address): delegate voting power to an address");
        console.log("- getVotes(address): get current voting power");
        console.log("- getPastVotes(address, uint256): get historical voting power");
        console.log("- getPastTotalSupply(uint256): get historical total supply");

        // Use BaseScript's verification helper
        _logVerificationCommand(newImplementation, "src/CNSTokenL2V2.sol:CNSTokenL2V2");
    }

    function _resolveProxyAddress(EnvConfig memory cfg) internal view returns (address) {
        // 1) Try environment variable first
        address fromEnv = address(0);
        try vm.envAddress("CNS_TOKEN_L2_PROXY") returns (address a) {
            fromEnv = a;
        } catch {}
        if (fromEnv != address(0)) return fromEnv;

        // 2) Try config file if provided
        if (cfg.l2.proxy != address(0)) {
            return cfg.l2.proxy;
        }

        // 3) Fallback: infer from broadcast artifacts for current chain id
        address fromArtifacts = _inferL2ProxyFromBroadcast(block.chainid);
        return fromArtifacts;
    }
    // Removed local inference: use BaseScript helpers
}

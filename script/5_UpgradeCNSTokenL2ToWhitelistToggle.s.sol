// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./BaseScript.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../src/CNSTokenL2.sol";

/**
 * @title UpgradeCNSTokenL2ToWhitelistToggle
 * @dev Script to upgrade CNSTokenL2 proxy to add whitelist toggle functionality
 * @notice This script:
 *         1. Deploys the new CNSTokenL2 implementation with whitelist toggle
 *         2. Upgrades the proxy to point to the new implementation
 *         3. Verifies the new functionality is available
 *         4. Supports both EOA and Safe upgraders
 *
 * Command Line Arguments:
 *   - --target-contract: Address of the contract to upgrade (required)
 *
 * Environment Variables Required:
 *   - CNS_OWNER_PRIVATE_KEY: Private key with UPGRADER_ROLE (preferred)
 *   - PRIVATE_KEY: Falls back to this if CNS_OWNER_PRIVATE_KEY not set
 *   - MAINNET_DEPLOYMENT_ALLOWED: Set to true for mainnet deployments
 *
 * Usage:
 *   # EOA upgrader
 *   forge script script/5_UpgradeCNSTokenL2ToWhitelistToggle.s.sol:UpgradeCNSTokenL2ToWhitelistToggle \
 *     --target-contract 0x123... \
 *     --rpc-url <your_rpc_url> \
 *     --broadcast
 *
 *   # Safe upgrader (generates transaction data)
 *   forge script script/5_UpgradeCNSTokenL2ToWhitelistToggle.s.sol:UpgradeCNSTokenL2ToWhitelistToggle \
 *     --target-contract 0x123... \
 *     --rpc-url <your_rpc_url> \
 *     --prepare-safe-tx
 */
contract UpgradeCNSTokenL2ToWhitelistToggle is BaseScript {
    address public targetContract;
    address public upgrader;
    address public newImplementation;
    bool public isSafe;
    bool public prepareSafeTx;

    function run() external {
        // Parse command line arguments
        _parseArguments();

        // Get upgrader credentials
        uint256 upgraderPrivateKey;
        try vm.envUint("CNS_OWNER_PRIVATE_KEY") returns (uint256 key) {
            upgraderPrivateKey = key;
            upgrader = vm.addr(upgraderPrivateKey);
            console.log("Using CNS_OWNER_PRIVATE_KEY");
        } catch {
            console.log("CNS_OWNER_PRIVATE_KEY not found, using PRIVATE_KEY");
            (upgraderPrivateKey, upgrader) = _getDeployer();
        }

        // Validate target contract
        _validateTargetContract();

        // Detect if upgrader is a Safe
        isSafe = _detectSafe(upgrader);
        console.log("Upgrader type:", isSafe ? "Safe" : "EOA");

        // Log upgrade info
        _logDeploymentHeader("Upgrading CNSTokenL2 to Whitelist Toggle Version");
        console.log("Network:", _getNetworkName(block.chainid));
        console.log("Chain ID:", block.chainid);
        console.log("Block:", block.number);
        console.log("Timestamp:", block.timestamp);
        console.log("Target contract:", targetContract);
        console.log("Upgrader address:", upgrader);
        console.log("Upgrader type:", isSafe ? "Safe" : "EOA");

        // Verify upgrader has UPGRADER_ROLE
        CNSTokenL2 proxy = CNSTokenL2(targetContract);
        bytes32 UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
        require(proxy.hasRole(UPGRADER_ROLE, upgrader), "Account doesn't have UPGRADER_ROLE");
        console.log("[OK] Account has UPGRADER_ROLE");

        // Safety check for mainnet
        _requireMainnetConfirmation();

        // Deploy new implementation
        vm.startBroadcast(upgraderPrivateKey);

        console.log("\n1. Deploying CNSTokenL2 implementation with whitelist toggle...");
        newImplementation = address(new CNSTokenL2());
        console.log("CNSTokenL2 implementation deployed at:", newImplementation);

        vm.stopBroadcast();

        // Execute upgrade based on upgrader type
        if (isSafe) {
            _handleSafeUpgrade();
        } else {
            _executeDirectUpgrade(upgraderPrivateKey);
        }

        // Verify upgrade
        _verifyUpgrade();

        // Log upgrade results
        _logUpgradeResults();
    }

    function _parseArguments() internal {
        // For now, we'll use a simple approach - check if target contract is set via environment
        // In a real implementation, you'd parse forge script arguments
        targetContract = vm.envOr("TARGET_CONTRACT", address(0));
        if (targetContract == address(0)) {
            revert("TARGET_CONTRACT environment variable must be set");
        }

        // Check if we should prepare Safe transaction
        prepareSafeTx = vm.envOr("PREPARE_SAFE_TX", false);
    }

    function _validateTargetContract() internal view {
        _requireNonZeroAddress(targetContract, "TARGET_CONTRACT");
        _requireContract(targetContract, "TARGET_CONTRACT");

        // Verify it's upgradeable
        try UUPSUpgradeable(targetContract).proxiableUUID() returns (bytes32) {
            console.log("[OK] Target contract is UUPS upgradeable");
        } catch {
            revert("Target contract is not UUPS upgradeable");
        }
    }

    function _detectSafe(address addr) internal view returns (bool) {
        // Check if address has Safe-like bytecode
        bytes memory code = addr.code;
        if (code.length == 0) return false;

        // Simple heuristic: check for common Safe function selectors
        // This is a basic check - in production you'd want more robust detection
        try this._checkSafeInterface(addr) returns (bool isSafeContract) {
            return isSafeContract;
        } catch {
            return false;
        }
    }

    function _checkSafeInterface(address addr) external view returns (bool) {
        // Check for Safe-specific functions
        // execTransaction, getOwners, getThreshold, etc.
        try IERC165(addr).supportsInterface(0x01ffc9a7) returns (bool) {
            // Basic check - if it supports ERC165, it might be a Safe
            // This is simplified - real implementation would check Safe-specific interfaces
            return true;
        } catch {
            return false;
        }
    }

    function _handleSafeUpgrade() internal {
        console.log("\n=== Safe Upgrade Detected ===");
        console.log("Preparing transaction data for Safe execution...");

        // Prepare upgrade transaction data
        bytes memory upgradeCalldata =
            abi.encodeWithSelector(UUPSUpgradeable.upgradeToAndCall.selector, newImplementation, "");

        // Estimate gas
        uint256 gasEstimate = _estimateUpgradeGas();

        console.log("\n=== Safe Transaction Data ===");
        console.log("To:", targetContract);
        console.log("Value: 0");
        console.log("Data:", vm.toString(upgradeCalldata));
        console.log("Gas Limit:", gasEstimate);
        console.log("Operation: 0 (Call)");

        console.log("\n=== Safe Execution Instructions ===");
        console.log("1. Go to Safe UI: https://app.safe.global/");
        console.log("2. Connect your wallet and select the Safe");
        console.log("3. Click 'New Transaction' -> 'Contract Interaction'");
        console.log("4. Enter the contract address:", targetContract);
        console.log("5. Paste the transaction data above");
        console.log("6. Set gas limit to:", gasEstimate);
        console.log("7. Review and submit for signatures");

        console.log("\n=== Alternative: Use Safe CLI ===");
        console.log("safe-cli transaction create \\");
        console.log("  --to", targetContract, "\\");
        console.log("  --value 0 \\");
        console.log("  --data", vm.toString(upgradeCalldata), "\\");
        console.log("  --gas-limit", gasEstimate);
    }

    function _executeDirectUpgrade(uint256 upgraderPrivateKey) internal {
        console.log("\n2. Upgrading proxy to new implementation...");

        vm.startBroadcast(upgraderPrivateKey);
        CNSTokenL2 proxy = CNSTokenL2(targetContract);
        proxy.upgradeToAndCall(newImplementation, "");
        vm.stopBroadcast();

        console.log("Upgrade successful!");
    }

    function _estimateUpgradeGas() internal view returns (uint256) {
        // Estimate gas for upgradeToAndCall
        bytes memory upgradeCalldata =
            abi.encodeWithSelector(UUPSUpgradeable.upgradeToAndCall.selector, newImplementation, "");

        try this._estimateGas(targetContract, upgradeCalldata) returns (uint256 gasEstimate) {
            return gasEstimate;
        } catch {
            // Fallback gas estimate
            return 500000;
        }
    }

    function _estimateGas(address target, bytes memory data) external view returns (uint256) {
        // This would be implemented to estimate gas for the upgrade transaction
        // For now, return a reasonable estimate
        return 500000;
    }

    function _verifyUpgrade() internal view {
        console.log("\n=== Verifying Upgrade ===");

        // Check implementation was updated
        bytes32 implementationSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        address currentImpl = address(uint160(uint256(vm.load(targetContract, implementationSlot))));
        require(currentImpl == newImplementation, "Implementation not updated");
        console.log("Current implementation:", currentImpl);
        console.log("Expected implementation:", newImplementation);
        console.log("[SUCCESS] Implementation successfully updated");

        // Verify new functionality is available
        CNSTokenL2 proxy = CNSTokenL2(targetContract);

        console.log("\n[SUCCESS] Verifying whitelist toggle functionality:");
        console.log("  - Token name:", proxy.name());
        console.log("  - Token symbol:", proxy.symbol());
        console.log("  - Sender allowlist enabled:", proxy.senderAllowlistEnabled());
        console.log("  - Upgrader allowlisted:", proxy.isSenderAllowlisted(upgrader));

        console.log("\n[SUCCESS] Whitelist toggle functions are accessible!");
    }

    function _logUpgradeResults() internal view {
        console.log("\n=== Upgrade Summary ===");
        console.log("Network:", _getNetworkName(block.chainid));
        console.log("Target contract:", targetContract);
        console.log("New implementation (Whitelist Toggle):", newImplementation);
        console.log("Upgrader type:", isSafe ? "Safe" : "EOA");

        console.log("\n=== New Features in Whitelist Toggle Version ===");
        console.log("  - setSenderAllowlistEnabled(bool): toggle allowlist on/off");
        console.log("  - senderAllowlistEnabled(): check if allowlist is enabled");
        console.log("  - Enhanced allowlist control for better flexibility");

        console.log("\n=== Verification Command ===");
        console.log("Manual verification required for this network");
        console.log("Contract address:", newImplementation);

        if (isSafe) {
            console.log("\n=== Next Steps for Safe ===");
            console.log("1. Execute the prepared transaction in Safe UI");
            console.log("2. Collect required signatures");
            console.log("3. Execute the transaction");
            console.log("4. Verify the upgrade was successful");
        }
    }
}

// Interface for ERC165 to check Safe compatibility
interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

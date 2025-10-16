// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "../src/CNSTokenL2.sol";

/**
 * @title CheckStorageLayout
 * @notice Helper script to verify storage layout for upgrade safety
 * @dev Run with: forge script script/CheckStorageLayout.s.sol
 */
contract CheckStorageLayout is Script {
    function run() external pure {
        console.log("=== CNSTokenL2 Storage Layout Analysis ===\n");

        // Get storage layout using forge inspect
        console.log("To generate storage layout, run:");
        console.log("  forge inspect CNSTokenL2 storage-layout\n");

        console.log("=== Upgrade Safety Guidelines ===\n");

        console.log("SAFE Operations:");
        console.log("  - Add new variables at the END of the contract");
        console.log("  - Use storage gap slots for new variables");
        console.log("  - Add new functions (they don't affect storage)");
        console.log("  - Modify function logic (storage layout unchanged)\n");

        console.log("UNSAFE Operations (WILL BREAK STORAGE):");
        console.log("  - Reorder existing state variables");
        console.log("  - Change variable types");
        console.log("  - Remove state variables");
        console.log("  - Insert variables between existing ones\n");

        console.log("=== Storage Gap Usage ===");
        console.log("Current gap: uint256[47] private __gap;");
        console.log("When adding N variables, reduce gap by N slots\n");

        console.log("=== Verification Steps ===");
        console.log("1. Generate current layout:");
        console.log("   forge inspect CNSTokenL2 storage-layout > layouts/current.json\n");

        console.log("2. Generate new version layout:");
        console.log("   forge inspect CNSTokenL2V2 storage-layout > layouts/v2.json\n");

        console.log("3. Compare layouts:");
        console.log("   diff layouts/current.json layouts/v2.json\n");

        console.log("4. Verify:");
        console.log("   - All existing variables at same slots");
        console.log("   - New variables use gap slots or append");
        console.log("   - Gap properly reduced\n");

        console.log("=== Run Upgrade Tests ===");
        console.log("forge test --match-contract CNSTokenL2UpgradeTest\n");
    }
}

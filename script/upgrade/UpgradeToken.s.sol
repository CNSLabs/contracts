// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../BaseScript.sol";
import "../../src/CNSTokenL2.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";

/**
 * @title UpgradeToken
 * @dev Complete upgrade process in a single script with visual progress indicators
 *
 * This script performs all upgrade steps sequentially:
 * 1. Validate Input Parameters
 * 2. Validate Target Contract
 * 3. Check Upgrader Permissions
 * 4. Detect Upgrader Type
 * 5. Deploy New Implementation
 * 6. Prepare Upgrade Transaction
 * 7. Execute Upgrade (if EOA) or provide Safe instructions
 *
 * Required Environment Variables (from input_params.env):
 * - TARGET_CONTRACT: The proxy contract to upgrade
 * - UPGRADER_ADDRESS: The address that will perform the upgrade
 * - RPC_URL: Network RPC URL
 *
 * Usage:
 * source script/upgrade/input_params.env
 * forge script script/upgrade/UpgradeToken.s.sol:UpgradeToken --rpc-url $RPC_URL --broadcast
 */
contract UpgradeToken is BaseScript {
    // Parameters
    address public targetContract;
    address public upgrader;
    address public newImplementation;
    address public currentImplementation;
    string public rpcUrl;
    uint256 public gasEstimate;
    bool public isSafe;
    bytes public upgradeCalldata;

    // Progress tracking
    uint256 public currentStep = 0;
    uint256 public constant TOTAL_STEPS = 7;

    function run() external {
        _printHeader();

        // Step 1: Validate Inputs
        _step1_ValidateInputs();

        // Step 2: Validate Target Contract
        _step2_ValidateTargetContract();

        // Step 3: Check Upgrader Permissions
        _step3_CheckUpgraderPermissions();

        // Step 4: Detect Upgrader Type
        _step4_DetectUpgraderType();

        // Step 5: Deploy Implementation
        _step5_DeployImplementation();

        // Step 6: Prepare Upgrade Transaction
        _step6_PrepareUpgradeTransaction();

        // Step 7: Final instructions (not executing for safety)
        _step7_FinalInstructions();

        _printFooter();
    }

    function _printHeader() internal view {
        console.log("\n");
        console.log("################################################################");
        console.log("##                                                            ##");
        console.log("##         CNS TOKEN L2 UPGRADE - ALL-IN-ONE SCRIPT           ##");
        console.log("##                                                            ##");
        console.log("################################################################");
        console.log("");
        console.log("Network:", _getNetworkName(block.chainid));
        console.log("Chain ID:", block.chainid);
        console.log("Block:", block.number);
        console.log("");
        console.log("This script will guide you through all upgrade steps");
        console.log("");
    }

    function _printStepHeader(string memory stepName) internal {
        currentStep++;
        console.log("\n");
        console.log("================================================================");
        console.log(
            string.concat("  STEP ", vm.toString(currentStep), " of ", vm.toString(TOTAL_STEPS), ": ", stepName)
        );
        console.log("================================================================");
        console.log("");
    }

    function _printStepSuccess(string memory message) internal view {
        console.log("");
        console.log("[SUCCESS]", message);
        console.log(
            string.concat("Progress: ", vm.toString(currentStep), "/", vm.toString(TOTAL_STEPS), " steps completed")
        );
        console.log("");
    }

    function _printProgress() internal view {
        console.log("");
        console.log("----------------------------------------------------------------");
        uint256 percentage = (currentStep * 100) / TOTAL_STEPS;
        console.log(
            string.concat(
                "Overall Progress: ",
                vm.toString(percentage),
                "% (",
                vm.toString(currentStep),
                "/",
                vm.toString(TOTAL_STEPS),
                " steps)"
            )
        );
        console.log("----------------------------------------------------------------");
        console.log("");
    }

    // STEP 1: Validate Inputs
    function _step1_ValidateInputs() internal {
        _printStepHeader("VALIDATE INPUT PARAMETERS");

        console.log("Loading parameters from environment...");

        // Load target contract
        targetContract = vm.envOr("TARGET_CONTRACT", address(0));
        if (targetContract == address(0)) {
            console.log("ERROR: TARGET_CONTRACT not set");
            console.log("Please set TARGET_CONTRACT in 0_input_params.env");
            revert("TARGET_CONTRACT not provided");
        }

        // Load upgrader address
        upgrader = vm.envOr("UPGRADER_ADDRESS", address(0));
        if (upgrader == address(0)) {
            console.log("ERROR: UPGRADER_ADDRESS not set");
            console.log("Please set UPGRADER_ADDRESS in 0_input_params.env");
            revert("UPGRADER_ADDRESS not provided");
        }

        // Load RPC URL
        try vm.envString("RPC_URL") returns (string memory url) {
            rpcUrl = url;
        } catch {
            console.log("WARNING: RPC_URL not set, using default");
            rpcUrl = "https://rpc.sepolia.linea.build";
        }

        gasEstimate = vm.envOr("GAS_LIMIT", uint256(500000));

        console.log("SUCCESS: Parameters loaded");
        console.log("  - Target Contract:", targetContract);
        console.log("  - Upgrader Address:", upgrader);
        console.log("  - RPC URL:", rpcUrl);
        console.log("  - Gas Limit:", gasEstimate);

        // Validate parameters
        if (targetContract == upgrader) {
            console.log("ERROR: Target contract and upgrader cannot be the same");
            revert("Invalid configuration");
        }

        _printStepSuccess("Input parameters validated");
        _printProgress();
    }

    // STEP 2: Validate Target Contract
    function _step2_ValidateTargetContract() internal {
        _printStepHeader("VALIDATE TARGET CONTRACT");

        console.log("Checking if contract exists...");

        // Check contract exists
        uint256 codeSize;
        address target = targetContract;
        assembly {
            codeSize := extcodesize(target)
        }

        if (codeSize == 0) {
            console.log("ERROR: No contract found at target address");
            revert("Contract does not exist");
        }

        console.log("SUCCESS: Contract exists (", codeSize, "bytes)");

        // Check if it's a proxy
        console.log("Checking if contract is a proxy...");
        bytes32 implementationSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        address implementation = address(uint160(uint256(vm.load(targetContract, implementationSlot))));

        if (implementation == address(0)) {
            console.log("ERROR: Target contract is not a proxy");
            revert("Target is not a proxy");
        }

        console.log("SUCCESS: Target is a proxy");
        console.log("  - Current implementation:", implementation);

        // Verify UUPS upgradeable
        console.log("Verifying UUPS upgradeability...");
        try UUPSUpgradeable(implementation).proxiableUUID() returns (bytes32) {
            console.log("SUCCESS: Implementation is UUPS upgradeable");
        } catch {
            console.log("ERROR: Implementation is not UUPS upgradeable");
            revert("Implementation not UUPS upgradeable");
        }

        _printStepSuccess("Target contract validated");
        _printProgress();
    }

    // STEP 3: Check Upgrader Permissions
    function _step3_CheckUpgraderPermissions() internal {
        _printStepHeader("CHECK UPGRADER PERMISSIONS");

        console.log("Checking UPGRADER_ROLE...");

        CNSTokenL2 proxy = CNSTokenL2(targetContract);
        bytes32 UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

        bool hasRole = proxy.hasRole(UPGRADER_ROLE, upgrader);

        if (!hasRole) {
            console.log("ERROR: Upgrader does not have UPGRADER_ROLE");
            console.log("Grant the role using:");
            console.log("  Target:", targetContract);
            console.log("  Function: grantRole(bytes32,address)");
            console.log("  Role:", vm.toString(UPGRADER_ROLE));
            console.log("  Account:", upgrader);
            revert("Upgrader lacks UPGRADER_ROLE");
        }

        console.log("SUCCESS: Upgrader has UPGRADER_ROLE");

        _printStepSuccess("Upgrader permissions verified");
        _printProgress();
    }

    // STEP 4: Detect Upgrader Type
    function _step4_DetectUpgraderType() internal {
        _printStepHeader("DETECT UPGRADER TYPE");

        console.log("Detecting upgrader type...");

        // Check if upgrader is a Safe
        bytes memory code = upgrader.code;
        if (code.length == 0) {
            isSafe = false;
        } else {
            try IERC165(upgrader).supportsInterface(0x01ffc9a7) returns (bool supported) {
                isSafe = supported;
            } catch {
                isSafe = false;
            }
        }

        if (isSafe) {
            console.log("SUCCESS: Upgrader is a Gnosis Safe");
            console.log("  Safe Address:", upgrader);
        } else {
            console.log("SUCCESS: Upgrader is an EOA");
            console.log("  EOA Address:", upgrader);
        }

        _printStepSuccess("Upgrader type detected");
        _printProgress();
    }

    // STEP 5: Deploy Implementation
    function _step5_DeployImplementation() internal {
        _printStepHeader("DEPLOY NEW IMPLEMENTATION");

        console.log("WARNING: This will deploy a new contract and cost gas fees");
        console.log("");

        // Get deployer private key
        uint256 deployerPrivateKey;
        try vm.envUint("CNS_TIMELOCK_PROPOSER_PRIVATE_KEY") returns (uint256 key) {
            deployerPrivateKey = key;
            console.log("Using CNS_TIMELOCK_PROPOSER_PRIVATE_KEY for deployment");
        } catch {
            (deployerPrivateKey,) = _getDeployer();
            console.log("Using PRIVATE_KEY for deployment");
        }

        // Deploy implementation
        vm.startBroadcast(deployerPrivateKey);
        console.log("Deploying CNSTokenL2 implementation...");
        newImplementation = address(new CNSTokenL2());
        vm.stopBroadcast();

        console.log("SUCCESS: Implementation deployed");
        console.log("  - New Implementation:", newImplementation);

        // Verify deployment
        uint256 codeSize;
        address impl = newImplementation;
        assembly {
            codeSize := extcodesize(impl)
        }

        console.log("  - Code size:", codeSize, "bytes");

        // Compare with current
        bytes32 implementationSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        currentImplementation = address(uint160(uint256(vm.load(targetContract, implementationSlot))));

        if (newImplementation == currentImplementation) {
            console.log("WARNING: New implementation is same as current");
        } else {
            console.log("SUCCESS: New implementation is different from current");
            console.log("  - Current:", currentImplementation);
            console.log("  - New:", newImplementation);
        }

        // Verify contract on block explorer
        _verifyImplementation();

        _printStepSuccess("New implementation deployed and verified");
        _printProgress();
    }

    function _verifyImplementation() internal {
        console.log("");
        console.log("Verifying contract on block explorer...");

        // Get API key based on chain
        string memory apiKey;
        string memory verifierUrl;

        if (block.chainid == 1) {
            // Ethereum Mainnet
            try vm.envString("ETHERSCAN_API_KEY") returns (string memory key) {
                apiKey = key;
                verifierUrl = "https://api.etherscan.io/api";
            } catch {
                console.log("INFO: ETHERSCAN_API_KEY not set, skipping verification");
                return;
            }
        } else if (block.chainid == 11155111) {
            // Ethereum Sepolia
            try vm.envString("ETHERSCAN_API_KEY") returns (string memory key) {
                apiKey = key;
                verifierUrl = "https://api-sepolia.etherscan.io/api";
            } catch {
                console.log("INFO: ETHERSCAN_API_KEY not set, skipping verification");
                return;
            }
        } else if (block.chainid == 59144) {
            // Linea Mainnet
            try vm.envString("LINEA_ETHERSCAN_API_KEY") returns (string memory key) {
                apiKey = key;
                verifierUrl = "https://api.lineascan.build/api";
            } catch {
                console.log("INFO: LINEA_ETHERSCAN_API_KEY not set, skipping verification");
                return;
            }
        } else if (block.chainid == 59141) {
            // Linea Sepolia
            try vm.envString("LINEA_ETHERSCAN_API_KEY") returns (string memory key) {
                apiKey = key;
                verifierUrl = "https://api-sepolia.lineascan.build/api";
            } catch {
                console.log("INFO: LINEA_ETHERSCAN_API_KEY not set, skipping verification");
                return;
            }
        } else {
            console.log("INFO: No verifier configured for this network, skipping verification");
            return;
        }

        if (bytes(apiKey).length == 0) {
            console.log("INFO: API key is empty, skipping verification");
            return;
        }

        console.log("Submitting verification request...");
        console.log("  - Contract:", newImplementation);
        console.log("  - Verifier:", verifierUrl);

        // Construct verification command using forge verify-contract
        string[] memory inputs = new string[](8);
        inputs[0] = "forge";
        inputs[1] = "verify-contract";
        inputs[2] = vm.toString(newImplementation);
        inputs[3] = "src/CNSTokenL2.sol:CNSTokenL2";
        inputs[4] = "--verifier-url";
        inputs[5] = verifierUrl;
        inputs[6] = "--etherscan-api-key";
        inputs[7] = apiKey;

        try vm.ffi(inputs) {
            console.log("SUCCESS: Contract verification submitted");
            console.log("Note: Verification may take a few minutes to complete");
        } catch {
            console.log("WARNING: Verification submission failed");
            console.log("You can verify manually using:");
            console.log("forge verify-contract", newImplementation, "src/CNSTokenL2.sol:CNSTokenL2");
            console.log("  --verifier-url", verifierUrl);
            console.log("  --etherscan-api-key <your_key>");
        }
    }

    // STEP 6: Prepare Upgrade Transaction
    function _step6_PrepareUpgradeTransaction() internal {
        _printStepHeader("PREPARE UPGRADE TRANSACTION");

        console.log("Generating upgrade transaction data...");

        // Generate upgradeToAndCall calldata
        upgradeCalldata = abi.encodeWithSelector(UUPSUpgradeable.upgradeToAndCall.selector, newImplementation, "");

        console.log("SUCCESS: Transaction data generated");
        console.log("  - Calldata length:", upgradeCalldata.length, "bytes");
        console.log("");

        console.log("=== UPGRADE TRANSACTION DATA ===");
        console.log("To:", targetContract);
        console.log("Value: 0");
        console.log("Data:", vm.toString(upgradeCalldata));
        console.log("Gas Limit:", gasEstimate);
        console.log("");

        _printStepSuccess("Upgrade transaction prepared");
        _printProgress();
    }

    // STEP 7: Final Instructions
    function _step7_FinalInstructions() internal {
        _printStepHeader("EXECUTION INSTRUCTIONS");

        if (isSafe) {
            console.log("SAFE EXECUTION REQUIRED");
            console.log("");
            console.log("Execute the upgrade via Safe UI:");
            console.log("");
            console.log("1. Go to: https://app.safe.global/");
            console.log("2. Select Safe:", upgrader);
            console.log("3. New Transaction -> Contract Interaction");
            console.log("4. Contract address:", targetContract);
            console.log("5. Transaction data:", vm.toString(upgradeCalldata));
            console.log("6. Gas limit:", gasEstimate);
            console.log("7. Review and submit for signatures");
            console.log("");
            console.log("Alternative - Safe CLI:");
            console.log("safe-cli transaction create \\");
            console.log("  --to", targetContract, "\\");
            console.log("  --value 0 \\");
            console.log("  --data", vm.toString(upgradeCalldata), "\\");
            console.log("  --gas-limit", gasEstimate);
        } else {
            console.log("EOA EXECUTION");
            console.log("");
            console.log("NOTE: For safety, this script does NOT automatically execute upgrades.");
            console.log("To execute, use one of these methods:");
            console.log("");
            console.log("Option 1 - Use cast:");
            console.log("cast send");
            console.log("  Target:", targetContract);
            console.log("  Function: upgradeToAndCall(address,bytes)");
            console.log("  Implementation:", newImplementation);
            console.log("  Data: 0x");
            console.log("  Options: --private-key <key> --rpc-url $RPC_URL");
            console.log("");
            console.log("Option 2 - Run this script with execution:");
            console.log("Use cast send (shown above) or Safe UI for manual execution");
        }

        console.log("");
        _printStepSuccess("All preparation steps completed");
        _printProgress();
    }

    function _printFooter() internal view {
        console.log("\n");
        console.log("################################################################");
        console.log("##                                                            ##");
        console.log("##              ALL PREPARATION STEPS COMPLETED               ##");
        console.log("##                                                            ##");
        console.log("################################################################");
        console.log("");
        console.log("SUMMARY:");
        console.log("  - Target Contract:", targetContract);
        console.log("  - New Implementation:", newImplementation);
        console.log("  - Upgrader:", upgrader);
        console.log("  - Upgrader Type:", isSafe ? "Gnosis Safe" : "EOA");
        console.log("  - Network:", _getNetworkName(block.chainid));
        console.log("");
        console.log("NEXT STEPS:");
        if (isSafe) {
            console.log("  1. Execute the transaction via Safe UI");
            console.log("  2. Collect required signatures");
            console.log("  3. Execute the transaction");
            console.log("  4. Verify upgrade success");
        } else {
            console.log("  1. Review the transaction data above");
            console.log("  2. Execute using cast or execution script");
            console.log("  3. Verify upgrade success");
        }
        console.log("");
        console.log("VERIFICATION:");
        console.log("After upgrade, verify with:");
        console.log("cast call", targetContract, "senderAllowlistEnabled() --rpc-url $RPC_URL");
        console.log("");
    }
}

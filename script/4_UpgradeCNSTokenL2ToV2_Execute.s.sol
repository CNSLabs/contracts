// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./BaseScript.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../src/CNSTokenL2V2.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title UpgradeCNSTokenL2ToV2_Execute
 * @dev Script to execute a previously scheduled CNSTokenL2 upgrade via TimelockController
 * @notice Executes an upgrade after the timelock delay has elapsed
 *
 * Environment Variables (Required):
 *   - PRIVATE_KEY or CNS_TIMELOCK_PROPOSER_PRIVATE_KEY: Executor key (must have EXECUTOR_ROLE on timelock,
 *     though we're currently not restricting proposal execution by granding 0x0 the EXECUTOR_ROLE role)
 *   - CNS_NEW_IMPLEMENTATION: Address of deployed V2 implementation
 *   - CNS_TIMELOCK_SALT: Salt used when scheduling
 *   - ENV: Select public config JSON
 *   - MAINNET_DEPLOYMENT_ALLOWED: Set to true for mainnet
 *
 * Usage:
 *   ENV=dev CNS_NEW_IMPLEMENTATION=0x... CNS_TIMELOCK_SALT=0x... \
 *   forge script script/4_UpgradeCNSTokenL2ToV2_Execute.s.sol:UpgradeCNSTokenL2ToV2_Execute \
 *     --rpc-url linea-sepolia --broadcast
 */
contract UpgradeCNSTokenL2ToV2_Execute is BaseScript {
    address public proxyAddress;
    address public newImplementation;
    address public timelockAddress;

    function run() external {
        EnvConfig memory cfg = _loadEnvConfig();
        uint256 executorPrivateKey;
        address executor;

        try vm.envUint("CNS_TIMELOCK_PROPOSER_PRIVATE_KEY") returns (uint256 key) {
            executorPrivateKey = key;
            executor = vm.addr(executorPrivateKey);
            console.log("Using CNS_TIMELOCK_PROPOSER_PRIVATE_KEY");
        } catch {
            console.log("CNS_TIMELOCK_PROPOSER_PRIVATE_KEY not found, using PRIVATE_KEY");
            (executorPrivateKey, executor) = _getDeployer();
        }

        // Get addresses from env vars
        newImplementation = vm.envAddress("CNS_NEW_IMPLEMENTATION");
        bytes32 salt = vm.envBytes32("CNS_TIMELOCK_SALT");

        _requireNonZeroAddress(newImplementation, "CNS_NEW_IMPLEMENTATION");

        proxyAddress = _resolveL2ProxyAddress(cfg);
        _requireNonZeroAddress(proxyAddress, "CNS_TOKEN_L2_PROXY (resolved)");
        _requireContract(proxyAddress, "CNS_TOKEN_L2_PROXY (resolved)");

        _logDeploymentHeader("Executing CNSTokenL2 to V2 Upgrade");
        console.log("Proxy address:", proxyAddress);
        console.log("New implementation:", newImplementation);
        console.log("Executor address:", executor);
        console.log("Timelock salt:", vm.toString(salt));

        _requireMainnetConfirmation();

        timelockAddress = _resolveL2TimelockAddress(cfg, proxyAddress);
        require(timelockAddress != address(0), "Missing TimelockController (set CNS_L2_TIMELOCK or config)");
        console.log("Using TimelockController:", timelockAddress);

        TimelockController tl = TimelockController(payable(timelockAddress));
        bytes32 executorRole = tl.EXECUTOR_ROLE();
        require(
            tl.hasRole(executorRole, executor) || tl.hasRole(executorRole, address(0)),
            "Missing EXECUTOR_ROLE on timelock"
        );

        // Prepare call data
        bytes memory initData = abi.encodeWithSelector(CNSTokenL2V2.initializeV2.selector);
        bytes memory callData =
            abi.encodeWithSelector(UUPSUpgradeable.upgradeToAndCall.selector, newImplementation, initData);

        bytes32 opId = tl.hashOperation(proxyAddress, 0, callData, bytes32(0), salt);

        // Check operation is ready
        uint8 state = uint8(tl.getOperationState(opId));
        require(state == 2, "Operation not ready (2=Ready, check delay has elapsed)");

        vm.startBroadcast(executorPrivateKey);

        console.log("\nExecuting upgrade...");
        tl.execute({target: proxyAddress, value: 0, payload: callData, predecessor: bytes32(0), salt: salt});

        vm.stopBroadcast();

        // Verify upgrade succeeded
        _verifyUpgrade();

        console.log("\n=== Upgrade Executed Successfully ===");
        console.log("Implementation:", newImplementation);
        console.log("Proxy:", proxyAddress);
    }

    function _verifyUpgrade() internal view {
        console.log("\n=== Verifying Upgrade ===");

        CNSTokenL2V2 proxy = CNSTokenL2V2(proxyAddress);

        bytes32 implementationSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        address implementationAddress = address(uint160(uint256(vm.load(proxyAddress, implementationSlot))));

        console.log("Current implementation:", implementationAddress);
        console.log("Expected implementation:", newImplementation);

        require(implementationAddress == newImplementation, "Implementation not updated!");
        console.log("[SUCCESS] Implementation successfully updated");

        console.log("\n[SUCCESS] Verifying V2 functionality:");
        console.log("  - Token name:", proxy.name());
        console.log("  - Token symbol:", proxy.symbol());
        console.log("  - Clock mode:", proxy.clock());
        console.log("  - CLOCK_MODE:", proxy.CLOCK_MODE());
        console.log("\n[SUCCESS] V2 voting functions are accessible!");
    }
}

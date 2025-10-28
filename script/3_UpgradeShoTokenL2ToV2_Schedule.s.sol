// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./BaseScript.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../src/ShoTokenL2.sol";
import "../src/ShoTokenL2V2.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title UpgradeShoTokenL2ToV2_Schedule
 * @dev Script to schedule ShoTokenL2 upgrade from V1 to V2 via TimelockController
 * @notice Deploys new implementation and schedules the upgrade via timelock
 *
 * Environment Variables:
 *   - PRIVATE_KEY: Signer key (must have PROPOSER_ROLE on timelock)
 *   - CNS_TIMELOCK_PROPOSER_PRIVATE_KEY: Alternative to PRIVATE_KEY
 *   - ENV: Select public config JSON
 *   - MAINNET_DEPLOYMENT_ALLOWED: Set to true for mainnet
 *
 * Usage:
 *   ENV=dev forge script script/3_UpgradeShoTokenL2ToV2_Schedule.s.sol:UpgradeShoTokenL2ToV2_Schedule \
 *     --rpc-url linea-sepolia --broadcast
 *
 * Output:
 *   - Prints NEW_IMPL_ADDRESS and TIMELOCK_SALT needed for execution
 */
contract UpgradeShoTokenL2ToV2_Schedule is BaseScript {
    address public proxyAddress;
    address public newImplementation;
    address public timelockAddress;

    function run() external {
        EnvConfig memory cfg = _loadEnvConfig();
        uint256 ownerPrivateKey;
        address owner;

        try vm.envUint("CNS_TIMELOCK_PROPOSER_PRIVATE_KEY") returns (uint256 key) {
            ownerPrivateKey = key;
            owner = vm.addr(ownerPrivateKey);
            console.log("Using CNS_TIMELOCK_PROPOSER_PRIVATE_KEY");
        } catch {
            console.log("CNS_TIMELOCK_PROPOSER_PRIVATE_KEY not found, using PRIVATE_KEY");
            (ownerPrivateKey, owner) = _getDeployer();
        }

        proxyAddress = _resolveL2ProxyAddress(cfg);
        _requireNonZeroAddress(proxyAddress, "CNS_TOKEN_L2_PROXY (resolved)");
        _requireContract(proxyAddress, "CNS_TOKEN_L2_PROXY (resolved)");

        _logDeploymentHeader("Scheduling ShoTokenL2 to V2 Upgrade");
        console.log("Proxy address:", proxyAddress);
        console.log("Proposer address:", owner);

        _requireMainnetConfirmation();

        timelockAddress = _resolveL2TimelockAddress(cfg, proxyAddress);
        require(timelockAddress != address(0), "Missing TimelockController (set CNS_L2_TIMELOCK or config)");
        console.log("Using TimelockController:", timelockAddress);

        TimelockController tl = TimelockController(payable(timelockAddress));
        bytes32 proposerRole = tl.PROPOSER_ROLE();
        require(tl.hasRole(proposerRole, owner), "Missing PROPOSER_ROLE on timelock");

        vm.startBroadcast(ownerPrivateKey);

        // Deploy new V2 implementation
        console.log("\n1. Deploying ShoTokenL2V2 implementation...");
        ShoTokenL2V2 implementationV2 = new ShoTokenL2V2();
        newImplementation = address(implementationV2);
        console.log("ShoTokenL2V2 implementation deployed at:", newImplementation);

        // Schedule upgrade
        console.log("\n2. Scheduling upgrade via Timelock...");
        bytes memory initData = abi.encodeWithSelector(ShoTokenL2V2.initializeV2.selector);
        bytes memory callData =
            abi.encodeWithSelector(UUPSUpgradeable.upgradeToAndCall.selector, newImplementation, initData);

        bytes32 salt = keccak256(abi.encodePacked("ShoTokenL2V2", newImplementation));
        uint256 delay = tl.getMinDelay();

        tl.schedule({target: proxyAddress, value: 0, data: callData, predecessor: bytes32(0), salt: salt, delay: delay});

        vm.stopBroadcast();

        // Verify and display results
        bytes32 opId = tl.hashOperation(proxyAddress, 0, callData, bytes32(0), salt);
        uint256 ts = tl.getTimestamp(opId);

        console.log("\n=== Upgrade Scheduled ===");
        console.log("Implementation Address:", newImplementation);
        console.log("Timelock Salt:", vm.toString(salt));
        console.log("Operation ID:", vm.toString(opId));
        console.log("Delay (seconds):", delay);
        console.log("Ready at timestamp:", ts);

        console.log("\n=== NEXT STEP ===");
        console.log("After %d seconds, execute with:", delay);
        console.log("CNS_NEW_IMPLEMENTATION=%s \\", newImplementation);
        console.log("CNS_TIMELOCK_SALT=%s \\", vm.toString(salt));
        console.log(
            "ENV=dev forge script script/4_UpgradeCNSTokenL2ToV2_Execute.s.sol:UpgradeCNSTokenL2ToV2_Execute \\"
        );
        console.log("  --rpc-url %s --broadcast", _getRpcEndpointName(block.chainid));

        // Log verification command for V2 implementation
        _logVerificationCommand(newImplementation, "src/CNSTokenL2V2.sol:ShoTokenL2V2");
    }
}

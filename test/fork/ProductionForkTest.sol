// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ConfigLoader, EnvConfig} from "../../script/ConfigLoader.sol";
import {BaseScript} from "../../script/BaseScript.sol";
import {CNSTokenL2} from "../../src/CNSTokenL2.sol";

/**
 * @title ProductionForkTest
 * @notice Base contract for testing production contracts on forked mainnet state
 * @dev Provides utilities for impersonating Safe multisig, bypassing timelock delays,
 *      and executing upgrades on production-like state
 */
abstract contract ProductionForkTest is Test, BaseScript {
    // Configuration loaded from JSON files
    EnvConfig config = _loadEnvConfig();

    // Contract addresses from production
    address internal cnsTokenL2Proxy;
    address internal timelockController;
    address internal safeMultisig;

    // Test configuration
    uint256 internal forkBlockNumber;
    string internal forkUrl;

    // Events for tracking
    event SafeImpersonated(address safe);
    event TimelockBypassed(uint256 delay);
    event UpgradeExecuted(address newImplementation);

    function setUp() public virtual {
        // Determine fork parameters
        forkUrl = _getForkUrl();
        forkBlockNumber = _getForkBlockNumber();

        uint256 forkId;

        // Create fork
        if (forkBlockNumber != 0) {
            forkId = vm.createFork(forkUrl, forkBlockNumber);
            console.log("Fork created at specific block:", forkBlockNumber);
        } else {
            forkId = vm.createFork(forkUrl);
            console.log("Fork created at latest block");
        }
        vm.selectFork(forkId);

        // Load production contract addresses
        _loadProductionAddresses();

        // Verify fork state
        _verifyForkState();
    }

    /**
     * @notice Bypass timelock delay by advancing time
     * @param timelockAddress The timelock controller address
     */
    function _bypassTimelockDelay(address timelockAddress) internal {
        // Get current timelock delay
        bytes memory delayCall = abi.encodeWithSignature("getMinDelay()");
        (, bytes memory delayData) = timelockAddress.call(delayCall);
        uint256 delay = abi.decode(delayData, (uint256));

        // Advance time past the delay
        uint256 currentTime = block.timestamp;
        vm.warp(currentTime + delay + 1);

        // Mine a new block to ensure timestamp is updated
        vm.roll(block.number + 1);

        emit TimelockBypassed(delay);
    }

    /**
     * @notice Execute a transaction through the Safe multisig (bypassing signature requirements)
     * @param safeAddress The Safe multisig address
     * @param to Target contract address
     * @param value ETH value to send
     * @param data Calldata for the transaction
     */
    function _executeSafeTransaction(
        address safeAddress,
        address to,
        uint256 value,
        bytes memory data,
        uint8 /* operation */
    )
        internal
        returns (bool success, bytes memory returnData)
    {
        // Impersonate the Safe
        vm.startPrank(safeAddress);

        (success, returnData) = to.call{value: value}(data);

        vm.stopPrank();

        if (!success) {
            console.log("Safe transaction failed:");
            console.logBytes(returnData);
        }
    }

    /**
     * @notice Schedule an upgrade through the timelock
     * @param timelockAddress The timelock controller address
     * @param newImplementation The new implementation address
     */
    function _scheduleUpgrade(
        address timelockAddress,
        address,
        /* target */
        address newImplementation
    )
        internal
    {
        // Encode the initialization data for V2 upgrade (like the working script)
        bytes memory initData = abi.encodeWithSignature("initializeV2()");

        // Encode the upgradeToAndCall call (like the working script)
        bytes memory upgradeCalldata =
            abi.encodeWithSignature("upgradeToAndCall(address,bytes)", newImplementation, initData);

        // Generate a proper salt (like the working script)
        bytes32 salt = keccak256(abi.encodePacked("CNSTokenL2V2", newImplementation));

        // Encode the timelock schedule call
        bytes memory scheduleCalldata = abi.encodeWithSignature(
            "schedule(address,uint256,bytes,bytes32,bytes32,uint256)",
            cnsTokenL2Proxy, // Call the proxy directly, not the proxy admin
            0, // value
            upgradeCalldata,
            bytes32(0), // predecessor
            salt, // use proper salt instead of bytes32(0)
            _getTimelockDelay(timelockAddress)
        );

        // Execute through Safe
        (bool success,) = _executeSafeTransaction(safeMultisig, timelockAddress, 0, scheduleCalldata, 0);

        require(success, "Failed to schedule upgrade");
        console.log("Upgrade scheduled successfully");
    }

    /**
     * @notice Execute a scheduled upgrade through the timelock
     * @param timelockAddress The timelock controller address
     * @param newImplementation The new implementation address
     */
    function _executeUpgrade(
        address timelockAddress,
        address,
        /* target */
        address newImplementation
    )
        internal
    {
        // Encode the initialization data for V2 upgrade (like the working script)
        bytes memory initData = abi.encodeWithSignature("initializeV2()");

        // Encode the upgradeToAndCall call (like the working script)
        bytes memory upgradeCalldata =
            abi.encodeWithSignature("upgradeToAndCall(address,bytes)", newImplementation, initData);

        // Generate the same salt used in scheduling (like the working script)
        bytes32 salt = keccak256(abi.encodePacked("CNSTokenL2V2", newImplementation));

        // Encode the timelock execute call
        bytes memory executeCalldata = abi.encodeWithSignature(
            "execute(address,uint256,bytes,bytes32,bytes32)",
            cnsTokenL2Proxy, // Call the proxy directly, not the proxy admin
            0, // value
            upgradeCalldata,
            bytes32(0), // predecessor
            salt // use the same salt as scheduling
        );

        // Execute through Safe
        (bool success,) = _executeSafeTransaction(safeMultisig, timelockAddress, 0, executeCalldata, 0);

        require(success, "Failed to execute upgrade");
        emit UpgradeExecuted(newImplementation);
        console.log("Upgrade executed successfully");
    }

    /**
     * @notice Get the timelock delay
     * @param timelockAddress The timelock controller address
     * @return delay The minimum delay in seconds
     */
    function _getTimelockDelay(address timelockAddress) internal view returns (uint256 delay) {
        bytes memory delayCall = abi.encodeWithSignature("getMinDelay()");
        (, bytes memory delayData) = timelockAddress.staticcall(delayCall);
        delay = abi.decode(delayData, (uint256));
    }

    /**
     * @notice Verify that the fork state matches production expectations
     */
    function _verifyForkState() internal view {
        require(cnsTokenL2Proxy != address(0), "CNS Token L2 proxy not found");
        require(timelockController != address(0), "Timelock controller not found");
        require(safeMultisig != address(0), "Safe multisig not found");

        // Verify contracts exist
        require(cnsTokenL2Proxy.code.length > 0, "CNS Token L2 proxy has no code");
        require(timelockController.code.length > 0, "Timelock controller has no code");
        require(safeMultisig.code.length > 0, "Safe multisig has no code");

        console.log("Fork state verified successfully");
        console.log("CNS Token L2 Proxy:", cnsTokenL2Proxy);
        console.log("Timelock Controller:", timelockController);
        console.log("Safe Multisig:", safeMultisig);
    }

    /**
     * @notice Load production contract addresses from configuration
     */
    function _loadProductionAddresses() internal {
        console.log("Loading addresses from config for env:", config.env);

        cnsTokenL2Proxy = config.l2.proxy;
        timelockController = config.l2.timelock.addr;
        safeMultisig = config.l2.roles.admin; // Assuming admin is the Safe

        console.log("CNS Token L2 Proxy:", cnsTokenL2Proxy);
        console.log("Timelock Controller:", timelockController);
        console.log("Safe Multisig:", safeMultisig);
    }

    /**
     * @notice Get the fork URL based on environment
     * @return url The RPC URL for forking
     */
    function _getForkUrl() internal view returns (string memory url) {
        if (keccak256(bytes(config.env)) == keccak256(bytes("production"))) {
            url = vm.envOr("LINEA_MAINNET_RPC_URL", string(""));
            console.log("Using production RPC URL:", url);
        } else {
            url = vm.envOr("LINEA_SEPOLIA_RPC_URL", string(""));
            console.log("Using dev RPC URL:", url);
        }

        require(bytes(url).length > 0, "RPC URL not set - check your environment variables");
        return url;
    }

    /**
     * @notice Get the fork block number
     * @return blockNumber The block number to fork from
     * @dev Defaults to latest block - 10, but can be overridden with FORK_BLOCK_NUMBER env var
     */
    function _getForkBlockNumber() internal view returns (uint256 blockNumber) {
        // Check if user provided a specific block number
        uint256 overrideBlock = vm.envOr("FORK_BLOCK_NUMBER", uint256(0));
        if (overrideBlock != 0) {
            return overrideBlock;
        }
        return 0;
    }

    /**
     * @notice Verify upgrade was successful
     * @param newImplementation The new implementation address
     */
    function _verifyUpgrade(address newImplementation) internal view {
        // Get the current implementation from storage (like the working script)
        bytes32 implementationSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        address currentImpl = address(uint160(uint256(vm.load(cnsTokenL2Proxy, implementationSlot))));

        require(currentImpl == newImplementation, "Upgrade verification failed");
        console.log("Upgrade verified successfully");
        console.log("Current implementation:", currentImpl);
        console.log("Expected implementation:", newImplementation);
    }
}

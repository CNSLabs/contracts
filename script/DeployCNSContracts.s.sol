// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/CNSTokenL1.sol";
import "../src/CNSTokenL2.sol";

/**
 * @title DeployCNSContracts
 * @dev Deployment script for CNS contract ecosystem
 */
contract DeployCNSContracts is Script {
    address public owner;

    // Contract instances
    CNSTokenL1 public tokenL1;
    CNSTokenL2 public tokenL2;
    address public tokenL2Implementation;

    string internal constant L2_NAME = "CNS Linea Token";
    string internal constant L2_SYMBOL = "CNSL";
    uint8 internal constant L2_DECIMALS = 18;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        owner = vm.envAddress("CNS_OWNER");

        string memory l1RpcUrl = vm.envOr("L1_RPC_URL", string(""));
        string memory l2RpcUrl = vm.envOr("L2_RPC_URL", string(""));

        if (bytes(l1RpcUrl).length > 0) vm.setEnv("FOUNDRY_ETH_RPC_URL", l1RpcUrl);
        if (bytes(l2RpcUrl).length > 0) vm.setEnv("FOUNDRY_LINEA_RPC_URL", l2RpcUrl);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy L1 Token
        console.log("Deploying CNSTokenL1...");
        tokenL1 = new CNSTokenL1(
            "Canonical CNS Token",
            "CNS",
            100_000_000 * 10 ** 18, // 100M tokens with 18 decimals
            owner
        );
        console.log("CNSTokenL1 deployed at:", address(tokenL1));

        // Deploy L2 Token implementation + proxy
        console.log("Deploying CNSTokenL2 implementation...");
        CNSTokenL2 implementation = new CNSTokenL2();
        tokenL2Implementation = address(implementation);
        console.log("CNSTokenL2 implementation deployed at:", tokenL2Implementation);

        address lineaL2Bridge = vm.envAddress("LINEA_L2_BRIDGE");

        bytes memory initCalldata = abi.encodeWithSelector(
            CNSTokenL2.initialize.selector, owner, lineaL2Bridge, address(tokenL1), L2_NAME, L2_SYMBOL, L2_DECIMALS
        );

        console.log("Deploying CNSTokenL2 proxy...");
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initCalldata);
        tokenL2 = CNSTokenL2(address(proxy));
        console.log("CNSTokenL2 proxy deployed at:", address(tokenL2));

        vm.stopBroadcast();

        // Log deployment summary
        _logDeploymentSummary();
    }

    function _logDeploymentSummary() internal view {
        console.log("\n=== CNS Contract Deployment Summary ===");
        console.log("Owner:", owner);
        console.log("CNSTokenL1:", address(tokenL1));
        console.log("CNSTokenL2 proxy:", address(tokenL2));
        console.log("CNSTokenL2 implementation:", tokenL2Implementation);
    }
}

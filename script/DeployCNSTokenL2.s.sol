// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/CNSTokenL2.sol";

/**
 * @title DeployCNSTokenL2
 * @dev L2-only deployment script for CNS Token on Linea Sepolia
 */
contract DeployCNSTokenL2 is Script {
    address public owner;
    CNSTokenL2 public tokenL2;
    address public tokenL2Implementation;

    string internal constant L2_NAME = "CNS Linea Token";
    string internal constant L2_SYMBOL = "CNSL";
    uint8 internal constant L2_DECIMALS = 18;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        owner = vm.envAddress("CNS_OWNER");
        address l1Token = vm.envAddress("L1_TOKEN_ADDRESS");
        address lineaL2Bridge = vm.envAddress("LINEA_L2_BRIDGE");
        string memory l2RpcUrl = vm.envString("L2_RPC_URL");

        // Create L2 fork
        uint256 l2Fork = vm.createFork(l2RpcUrl);
        vm.selectFork(l2Fork);

        console.log("\n=== Deploying to L2 (Linea Sepolia) ===");
        console.log("L1 Token:", l1Token);
        console.log("Owner:", owner);
        console.log("Bridge:", lineaL2Bridge);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy L2 Token implementation
        console.log("\nDeploying CNSTokenL2 implementation...");
        CNSTokenL2 implementation = new CNSTokenL2();
        tokenL2Implementation = address(implementation);
        console.log("CNSTokenL2 implementation deployed at:", tokenL2Implementation);

        // Deploy proxy
        bytes memory initCalldata = abi.encodeWithSelector(
            CNSTokenL2.initialize.selector, owner, lineaL2Bridge, l1Token, L2_NAME, L2_SYMBOL, L2_DECIMALS
        );

        console.log("Deploying CNSTokenL2 proxy...");
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initCalldata);
        tokenL2 = CNSTokenL2(address(proxy));
        console.log("CNSTokenL2 proxy deployed at:", address(tokenL2));

        vm.stopBroadcast();

        // Print verification commands
        _printVerificationCommands(tokenL2Implementation, address(tokenL2), initCalldata);

        // Log deployment summary
        _logDeploymentSummary();
    }

    function _printVerificationCommands(address implementation, address proxyAddress, bytes memory initCalldata)
        internal
        pure
    {
        console.log("\n=== L2 Verification Commands ===");

        // Print implementation verification command
        console.log("\n1. Verify CNSTokenL2 implementation:");
        console.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(implementation),
                " src/CNSTokenL2.sol:CNSTokenL2 --chain linea-sepolia --verifier blockscout --verifier-url https://api-sepolia.lineascan.build/api --watch"
            )
        );

        console.log("\n2. Verify ERC1967Proxy:");
        console.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(proxyAddress),
                " lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy --chain linea-sepolia --verifier blockscout --verifier-url https://api-sepolia.lineascan.build/api --constructor-args ",
                vm.toString(abi.encode(implementation, initCalldata)),
                " --watch"
            )
        );
    }

    function _logDeploymentSummary() internal view {
        console.log("\n=== CNS L2 Deployment Summary ===");
        console.log("Owner:", owner);
        console.log("CNSTokenL2 implementation (Linea Sepolia):", tokenL2Implementation);
        console.log("CNSTokenL2 proxy (Linea Sepolia):", address(tokenL2));
    }
}

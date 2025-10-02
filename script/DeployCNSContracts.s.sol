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

        string memory l1RpcUrl = vm.envString("ETH_SEPOLIA_RPC_URL");
        string memory l2RpcUrl = vm.envString("LINEA_SEPOLIA_RPC_URL");
        string memory etherscanApiKey = vm.envString("ETHERSCAN_API_KEY");
        string memory lineaEtherscanApiKey = vm.envString("LINEA_ETHERSCAN_API_KEY");

        // Create forks for both chains
        uint256 l1Fork = vm.createFork(l1RpcUrl);
        uint256 l2Fork = vm.createFork(l2RpcUrl);

        // Deploy L1 Token on Ethereum Sepolia
        console.log("\n=== Deploying to L1 (Ethereum Sepolia) ===");
        vm.selectFork(l1Fork);
        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying CNSTokenL1...");
        tokenL1 = new CNSTokenL1(
            "Canonical CNS Token",
            "CNS",
            100_000_000 * 10 ** 18, // 100M tokens with 18 decimals
            owner
        );
        console.log("CNSTokenL1 deployed at:", address(tokenL1));

        vm.stopBroadcast();

        // Verify L1 contract
        _verifyL1Contract(address(tokenL1), etherscanApiKey);

        // Deploy L2 Token on Linea Sepolia
        console.log("\n=== Deploying to L2 (Linea Sepolia) ===");
        vm.selectFork(l2Fork);
        vm.startBroadcast(deployerPrivateKey);

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

        // Verify L2 contracts
        _verifyL2Contracts(tokenL2Implementation, address(tokenL2), initCalldata, lineaEtherscanApiKey);

        // Log deployment summary
        _logDeploymentSummary();
    }

    function _verifyL1Contract(address tokenL1Address, string memory apiKey) internal pure {
        console.log("\n=== L1 Verification Command ===");
        console.log("Run this command to verify CNSTokenL1:");
        console.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(tokenL1Address),
                " src/CNSTokenL1.sol:CNSTokenL1 --chain sepolia --etherscan-api-key ",
                apiKey,
                " --watch"
            )
        );
    }

    function _verifyL2Contracts(
        address implementation,
        address proxyAddress,
        bytes memory initCalldata,
        string memory /* apiKey */
    ) internal pure {
        console.log("\n=== L2 Verification Commands ===");

        // Print implementation verification command
        console.log("1. Verify CNSTokenL2 implementation:");
        console.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(implementation),
                " src/CNSTokenL2.sol:CNSTokenL2 --chain linea-sepolia --watch"
            )
        );

        console.log("\n2. Verify ERC1967Proxy:");
        console.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(proxyAddress),
                " lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy --chain linea-sepolia --constructor-args ",
                vm.toString(abi.encode(implementation, initCalldata)),
                " --watch"
            )
        );
    }

    function _logDeploymentSummary() internal view {
        console.log("\n=== CNS Contract Deployment Summary ===");
        console.log("Owner:", owner);
        console.log("CNSTokenL1 (Ethereum Sepolia):", address(tokenL1));
        console.log("CNSTokenL2 implementation (Linea Sepolia):", tokenL2Implementation);
        console.log("CNSTokenL2 proxy (Linea Sepolia):", address(tokenL2));
    }
}

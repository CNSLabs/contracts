// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "../src/CNSTokenL1.sol";
import "../src/CNSAccessNFT.sol";
import "../src/CNSTierProgression.sol";
import "../src/CNSTokenSale.sol";
import "../src/CNSTokenL2.sol";
import "../src/CNSAccessControl.sol";
import "../src/CREATE2Factory.sol";

/**
 * @title DeployCNSContracts
 * @dev Deployment script for CNS contract ecosystem
 */
contract DeployCNSContracts is Script {
    // Deployment addresses
    address public owner = address(0x1234); // Replace with actual owner address

    // Deterministic deployment salts
    bytes32 public constant TOKEN_L1_SALT = keccak256("CNS_TOKEN_L1_V1");
    bytes32 public constant TOKEN_L2_SALT = keccak256("CNS_TOKEN_L2_V1");

    // Contract instances
    CREATE2Factory public factory;
    CNSTokenL1 public tokenL1;
    CNSAccessNFT public accessNFT;
    CNSTierProgression public tierProgression;
    CNSTokenSale public tokenSale;
    CNSTokenL2 public tokenL2;
    CNSAccessControl public accessControl;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy CREATE2 Factory
        console.log("Deploying CREATE2Factory...");
        factory = new CREATE2Factory();
        console.log("CREATE2Factory deployed at:", address(factory));

        // Pre-calculate deterministic token addresses
        address predictedTokenL1 = factory.calculateAddress(type(CNSTokenL1).creationCode, TOKEN_L1_SALT);
        address predictedTokenL2 = factory.calculateAddress(
            abi.encodePacked(type(CNSTokenL2).creationCode, abi.encode(owner, predictedTokenL1)), TOKEN_L2_SALT
        );

        console.log("Predicted CNSTokenL1 address:", predictedTokenL1);
        console.log("Predicted CNSTokenL2 address:", predictedTokenL2);

        // Deploy L1 Token with CREATE2
        console.log("Deploying CNSTokenL1 with CREATE2...");
        bytes memory tokenL1Bytecode = type(CNSTokenL1).creationCode;
        address deployedTokenL1 = factory.deploy(tokenL1Bytecode, TOKEN_L1_SALT);
        tokenL1 = CNSTokenL1(deployedTokenL1);
        require(address(tokenL1) == predictedTokenL1, "Token L1 address mismatch");
        console.log("CNSTokenL1 deployed at:", address(tokenL1));

        // Deploy Access NFT (regular deployment)
        console.log("Deploying CNSAccessNFT...");
        accessNFT = new CNSAccessNFT(owner, "https://api.cns.com/nft/");
        console.log("CNSAccessNFT deployed at:", address(accessNFT));

        // Deploy Tier Progression (regular deployment)
        console.log("Deploying CNSTierProgression...");
        tierProgression = new CNSTierProgression(owner, address(accessNFT));
        console.log("CNSTierProgression deployed at:", address(tierProgression));

        // Deploy L2 Token with CREATE2
        console.log("Deploying CNSTokenL2 with CREATE2...");
        bytes memory tokenL2Bytecode =
            abi.encodePacked(type(CNSTokenL2).creationCode, abi.encode(owner, predictedTokenL1));
        address deployedTokenL2 = factory.deploy(tokenL2Bytecode, TOKEN_L2_SALT);
        tokenL2 = CNSTokenL2(deployedTokenL2);
        require(address(tokenL2) == predictedTokenL2, "Token L2 address mismatch");
        console.log("CNSTokenL2 deployed at:", address(tokenL2));

        // Deploy Access Control
        console.log("Deploying CNSAccessControl...");
        accessControl = new CNSAccessControl(owner, address(accessNFT), address(tierProgression));
        console.log("CNSAccessControl deployed at:", address(accessControl));

        // Deploy Token Sale
        console.log("Deploying CNSTokenSale...");
        tokenSale = new CNSTokenSale(
            address(tokenL2), // L2 token address
            address(accessNFT),
            address(tierProgression),
            owner
        );
        console.log("CNSTokenSale deployed at:", address(tokenSale));

        // Set up contracts
        _setupContracts();

        vm.stopBroadcast();

        // Log deployment summary
        _logDeploymentSummary();
    }

    function _setupContracts() internal {
        // Set bridge contract for L1 token
        tokenL1.setBridgeContract(address(this)); // Temporary - replace with actual bridge

        // Set bridge contract for L2 token
        tokenL2.setBridgeContract(address(this)); // Temporary - replace with actual bridge

        // Set tier prices for NFT
        accessNFT.setTierPrices(
            1 ether, // Tier 1: 1 ETH
            0.5 ether, // Tier 2: 0.5 ETH
            0.1 ether // Tier 3: 0.1 ETH
        );

        // Start the sale (1 day from now)
        uint256 saleStartTime = block.timestamp + 1 days;
        tierProgression.startSale(saleStartTime);

        console.log("Sale starts at:", saleStartTime);
        console.log("Tier 1 only until:", saleStartTime + 1 days);
        console.log("Tiers 1-2 until:", saleStartTime + 3 days);
        console.log("All tiers until:", saleStartTime + 10 days);
    }

    function _logDeploymentSummary() internal view {
        console.log("\n=== CNS Contract Deployment Summary ===");
        console.log("Owner:", owner);
        console.log("CREATE2Factory:", address(factory));
        console.log("CNSTokenL1 (CREATE2):", address(tokenL1));
        console.log("CNSAccessNFT:", address(accessNFT));
        console.log("CNSTierProgression:", address(tierProgression));
        console.log("CNSTokenL2 (CREATE2):", address(tokenL2));
        console.log("CNSAccessControl:", address(accessControl));
        console.log("CNSTokenSale:", address(tokenSale));

        console.log("\n=== Deterministic Deployment Info ===");
        console.log("Token L1 Salt:", uint256(TOKEN_L1_SALT));
        console.log("Token L2 Salt:", uint256(TOKEN_L2_SALT));

        console.log("\n=== Setup Information ===");
        console.log("Token Sale Price: 0.001 ETH per token");
        console.log("Min Purchase: 100 tokens");
        console.log("Max Purchase per user: 10,000 tokens");
        console.log("Total tokens for sale: 100,000,000");

        console.log("\n=== Tier Information ===");
        console.log("Tier 1 Price: 1.0 ETH");
        console.log("Tier 2 Price: 0.5 ETH");
        console.log("Tier 3 Price: 0.1 ETH");

        console.log("\n=== Timeline ===");
        console.log("Sale starts in 1 day");
        console.log("Day 1: Tier 1 only");
        console.log("Days 2-3: Tiers 1 & 2");
        console.log("Days 4-10: All tiers");
    }
}

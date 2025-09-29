// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "../src/CNSTokenL1.sol";
import "../src/CNSAccessNFT.sol";
import "../src/CNSTierProgression.sol";
import "../src/CNSTokenSale.sol";
import "../src/CNSTokenL2.sol";
import "../src/CNSAccessControl.sol";

/**
 * @title DeployCNSContracts
 * @dev Deployment script for CNS contract ecosystem
 */
contract DeployCNSContracts is Script {
    // Deployment addresses
    address public owner = address(0x1234); // Replace with actual owner address

    // Contract instances
    CNSTokenL1 public tokenL1;
    CNSAccessNFT public accessNFT;
    CNSTierProgression public tierProgression;
    CNSTokenSale public tokenSale;
    CNSTokenL2 public tokenL2;
    CNSAccessControl public accessControl;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy L1 Token
        console.log("Deploying CNSTokenL1...");
        tokenL1 = new CNSTokenL1(
            "Canonical CNS Token",
            "CNS", 
            100_000_000 * 10**18, // 100M tokens with 18 decimals
            owner
        );
        console.log("CNSTokenL1 deployed at:", address(tokenL1));

        // Deploy Access NFT
        console.log("Deploying CNSAccessNFT...");
        accessNFT = new CNSAccessNFT(
            owner,
            "https://api.cns.com/nft/"
        );
        console.log("CNSAccessNFT deployed at:", address(accessNFT));

        // Deploy Tier Progression
        console.log("Deploying CNSTierProgression...");
        tierProgression = new CNSTierProgression(
            owner,
            address(accessNFT)
        );
        console.log("CNSTierProgression deployed at:", address(tierProgression));

        // Deploy L2 Token
        console.log("Deploying CNSTokenL2...");
        tokenL2 = new CNSTokenL2(
            owner,
            address(tokenL1) // L1 token address
        );
        console.log("CNSTokenL2 deployed at:", address(tokenL2));

        // Deploy Access Control
        console.log("Deploying CNSAccessControl...");
        accessControl = new CNSAccessControl(
            owner,
            address(accessNFT),
            address(tierProgression)
        );
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
        // Note: CNSTokenL1 is a simple ERC20 with fixed supply - no bridge setup needed
        // The Linea canonical bridge will handle the L1->L2 bridging automatically

        // Set bridge contract for L2 token
        tokenL2.setBridgeContract(address(this)); // Temporary - replace with actual bridge

        // Set tier prices for NFT
        accessNFT.setTierPrices(
            1 ether,    // Tier 1: 1 ETH
            0.5 ether,  // Tier 2: 0.5 ETH
            0.1 ether   // Tier 3: 0.1 ETH
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
        console.log("CNSTokenL1:", address(tokenL1));
        console.log("CNSAccessNFT:", address(accessNFT));
        console.log("CNSTierProgression:", address(tierProgression));
        console.log("CNSTokenL2:", address(tokenL2));
        console.log("CNSAccessControl:", address(accessControl));
        console.log("CNSTokenSale:", address(tokenSale));

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

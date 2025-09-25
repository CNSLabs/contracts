// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/CNSAccessNFT.sol";

contract CNSAccessNFTTest is Test {
    CNSAccessNFT public nft;
    address public owner = address(0x123);
    address public user1 = address(0x456);
    address public user2 = address(0x789);

    function setUp() public {
        // Fund test accounts
        vm.deal(owner, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        nft = new CNSAccessNFT(owner, "https://api.cns.com/nft");
    }

    function testMintTier1() public {
        vm.prank(owner);
        nft.mintTier(user1, CNSAccessNFT.Tier.TIER1);

        assertEq(nft.balanceOf(user1), 1);
        assertEq(uint256(nft.getUserTier(user1)), uint256(CNSAccessNFT.Tier.TIER1));
        assertEq(nft.tokenURI(1), "https://api.cns.com/nft/1");
    }

    function testBuyTier1() public {
        vm.prank(owner);
        nft.toggleSale();

        vm.prank(user1);
        nft.buyTier{value: 1 ether}(CNSAccessNFT.Tier.TIER1);

        assertEq(nft.balanceOf(user1), 1);
        assertEq(uint256(nft.getUserTier(user1)), uint256(CNSAccessNFT.Tier.TIER1));
    }

    function testBuyTierWithExcessPayment() public {
        vm.prank(owner);
        nft.toggleSale();

        uint256 excessAmount = 2 ether;
        vm.prank(user1);
        nft.buyTier{value: excessAmount}(CNSAccessNFT.Tier.TIER1);

        assertEq(nft.balanceOf(user1), 1);
        assertEq(user1.balance, excessAmount - 1 ether); // Should get 1 ETH back
    }

    function testTierLimits() public {
        // Mint max Tier 1
        for (uint256 i = 0; i < nft.TIER1_LIMIT(); i++) {
            vm.prank(owner);
            nft.mintTier(user1, CNSAccessNFT.Tier.TIER1);
        }

        assertEq(nft.tierMinted(CNSAccessNFT.Tier.TIER1), nft.TIER1_LIMIT());
        assertEq(nft.tier1SoldOut(), true);
    }

    function testGetUserTier() public {
        // User with no NFTs should have NONE tier
        assertEq(uint256(nft.getUserTier(user1)), uint256(CNSAccessNFT.Tier.NONE));

        // Mint Tier 2
        vm.prank(owner);
        nft.mintTier(user1, CNSAccessNFT.Tier.TIER2);

        assertEq(uint256(nft.getUserTier(user1)), uint256(CNSAccessNFT.Tier.TIER2));

        // Mint Tier 1 (highest tier)
        vm.prank(owner);
        nft.mintTier(user1, CNSAccessNFT.Tier.TIER1);

        assertEq(uint256(nft.getUserTier(user1)), uint256(CNSAccessNFT.Tier.TIER1));
    }

    function testHasTierAccess() public {
        vm.prank(owner);
        nft.mintTier(user1, CNSAccessNFT.Tier.TIER2);

        assertEq(nft.hasTierAccess(user1, CNSAccessNFT.Tier.TIER2), true);
        assertEq(nft.hasTierAccess(user1, CNSAccessNFT.Tier.TIER1), false); // Lower tier
    }

    function testSetTierPrices() public {
        vm.prank(owner);
        nft.setTierPrices(2 ether, 1 ether, 0.5 ether);

        assertEq(nft.tier1Price(), 2 ether);
        assertEq(nft.tier2Price(), 1 ether);
        assertEq(nft.tier3Price(), 0.5 ether);
    }

    function testWithdraw() public {
        vm.prank(owner);
        nft.toggleSale();

        vm.prank(user1);
        nft.buyTier{value: 1 ether}(CNSAccessNFT.Tier.TIER1);

        uint256 initialBalance = owner.balance;
        vm.prank(owner);
        nft.withdraw();

        assertEq(owner.balance, initialBalance + 1 ether);
    }

    function testGetTierStats() public {
        vm.prank(owner);
        nft.mintTier(user1, CNSAccessNFT.Tier.TIER1);

        (uint256 tier1Minted, uint256 tier2Minted, uint256 tier3Minted, bool tier1Sold, bool tier2Sold, bool tier3Sold)
        = nft.getTierStats();

        assertEq(tier1Minted, 1);
        assertEq(tier2Minted, 0);
        assertEq(tier3Minted, 0);
        assertEq(tier1Sold, false);
        assertEq(tier2Sold, false);
        assertEq(tier3Sold, false);
    }

    function testSaleStateToggle() public {
        assertEq(nft.saleActive(), false);

        vm.prank(owner);
        nft.toggleSale();

        assertEq(nft.saleActive(), true);
    }
}

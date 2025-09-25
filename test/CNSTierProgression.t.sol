// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/CNSTierProgression.sol";
import "../src/CNSAccessNFT.sol";

contract CNSTierProgressionTest is Test {
    CNSTierProgression public tierProgression;
    CNSAccessNFT public accessNFT;

    address public owner = address(0x123);
    address public user1 = address(0x456);

    function setUp() public {
        // Fund test accounts
        vm.deal(owner, 100 ether);
        vm.deal(user1, 100 ether);

        accessNFT = new CNSAccessNFT(owner, "https://api.cns.com/nft/");
        tierProgression = new CNSTierProgression(owner, address(accessNFT));
    }

    function testInitialState() public {
        assertEq(tierProgression.saleStartTime(), 0);
        assertEq(uint256(tierProgression.getCurrentPhase()), uint256(CNSTierProgression.SalePhase.NOT_STARTED));
    }

    function testStartSale() public {
        uint256 startTime = block.timestamp + 1 days;

        vm.prank(owner);
        tierProgression.startSale(startTime);

        assertEq(tierProgression.saleStartTime(), startTime);
    }

    function testCannotStartSaleTwice() public {
        uint256 startTime = block.timestamp + 1 days;

        vm.prank(owner);
        tierProgression.startSale(startTime);

        vm.prank(owner);
        vm.expectRevert("CNSTierProgression: sale already started");
        tierProgression.startSale(startTime + 1 days);
    }

    function testTier1OnlyPhase() public {
        uint256 startTime = block.timestamp + 1 hours;

        vm.prank(owner);
        tierProgression.startSale(startTime);

        // Sale hasn't started yet, so phase should be NOT_STARTED
        assertEq(uint256(tierProgression.getCurrentPhase()), uint256(CNSTierProgression.SalePhase.NOT_STARTED));

        // Warp time to when the sale should be in TIER1_ONLY phase
        vm.warp(startTime + 12 hours); // Halfway through the first day

        assertEq(uint256(tierProgression.getCurrentPhase()), uint256(CNSTierProgression.SalePhase.TIER1_ONLY));
    }

    function testTier12Phase() public {
        uint256 startTime = block.timestamp + 1 hours;

        vm.prank(owner);
        tierProgression.startSale(startTime);

        // Warp time to TIER12 phase (1 day + 1 day)
        vm.warp(startTime + 1 days + 1 days);

        assertEq(uint256(tierProgression.getCurrentPhase()), uint256(CNSTierProgression.SalePhase.TIER12));
    }

    function testAllTiersPhase() public {
        uint256 startTime = block.timestamp + 1 hours;

        vm.prank(owner);
        tierProgression.startSale(startTime);

        // Warp time to ALL_TIERS phase (1 day + 2 days + 1 day)
        vm.warp(startTime + 1 days + 2 days + 1 days);

        assertEq(uint256(tierProgression.getCurrentPhase()), uint256(CNSTierProgression.SalePhase.ALL_TIERS));
    }

    function testEndedPhase() public {
        uint256 startTime = block.timestamp + 1 hours;

        vm.prank(owner);
        tierProgression.startSale(startTime);

        // Warp time to after the sale ends (1 day + 2 days + 7 days + 1 day)
        vm.warp(startTime + 1 days + 2 days + 7 days + 1 days);

        assertEq(uint256(tierProgression.getCurrentPhase()), uint256(CNSTierProgression.SalePhase.ENDED));
    }

    function testHasTierAccess() public {
        uint256 startTime = block.timestamp + 1 hours;

        vm.prank(owner);
        tierProgression.startSale(startTime);

        // Sale hasn't started yet, so no tier should have access
        assertEq(tierProgression.hasTierAccess(CNSTierProgression.Tier.TIER1), false);
        assertEq(tierProgression.hasTierAccess(CNSTierProgression.Tier.TIER2), false);
        assertEq(tierProgression.hasTierAccess(CNSTierProgression.Tier.TIER3), false);

        // Warp to TIER1_ONLY phase
        vm.warp(startTime + 12 hours);

        // Tier 1 only phase
        assertEq(tierProgression.hasTierAccess(CNSTierProgression.Tier.TIER1), true);
        assertEq(tierProgression.hasTierAccess(CNSTierProgression.Tier.TIER2), false);
        assertEq(tierProgression.hasTierAccess(CNSTierProgression.Tier.TIER3), false);

        // Advance to tier 1-2 phase
        vm.warp(startTime + 2 days);

        assertEq(tierProgression.hasTierAccess(CNSTierProgression.Tier.TIER1), true);
        assertEq(tierProgression.hasTierAccess(CNSTierProgression.Tier.TIER2), true);
        assertEq(tierProgression.hasTierAccess(CNSTierProgression.Tier.TIER3), false);

        // Advance to all tiers phase
        vm.warp(startTime + 5 days);

        assertEq(tierProgression.hasTierAccess(CNSTierProgression.Tier.TIER1), true);
        assertEq(tierProgression.hasTierAccess(CNSTierProgression.Tier.TIER2), true);
        assertEq(tierProgression.hasTierAccess(CNSTierProgression.Tier.TIER3), true);
    }

    function testGetTimeUntilNextPhase() public {
        uint256 startTime = block.timestamp + 1 hours;

        vm.prank(owner);
        tierProgression.startSale(startTime);

        (uint256 timeRemaining, CNSTierProgression.SalePhase nextPhase) = tierProgression.getTimeUntilNextPhase();

        assertEq(uint256(nextPhase), uint256(CNSTierProgression.SalePhase.TIER1_ONLY));
        assertEq(timeRemaining, startTime - block.timestamp);
    }

    function testGetPhaseInfo() public {
        uint256 startTime = block.timestamp + 1 hours;

        vm.prank(owner);
        tierProgression.startSale(startTime);

        (
            CNSTierProgression.SalePhase currentPhase,
            uint256 timeRemaining,
            CNSTierProgression.SalePhase nextPhase,
            bool isActive
        ) = tierProgression.getPhaseInfo();

        assertEq(uint256(currentPhase), uint256(CNSTierProgression.SalePhase.NOT_STARTED));
        assertEq(uint256(nextPhase), uint256(CNSTierProgression.SalePhase.TIER1_ONLY));
        assertEq(isActive, false);
        assertEq(timeRemaining, startTime - block.timestamp);
    }

    function testGetAllowedTiers() public {
        uint256 startTime = block.timestamp + 1 hours;

        vm.prank(owner);
        tierProgression.startSale(startTime);

        // Sale hasn't started yet, so no tiers should be allowed
        CNSTierProgression.Tier[] memory allowedTiers = tierProgression.getAllowedTiers();
        assertEq(allowedTiers.length, 0);

        // Advance to tier 1-2 phase
        vm.warp(startTime + 2 days);

        allowedTiers = tierProgression.getAllowedTiers();
        assertEq(allowedTiers.length, 2);
        assertEq(uint256(allowedTiers[0]), uint256(CNSTierProgression.Tier.TIER1));
        assertEq(uint256(allowedTiers[1]), uint256(CNSTierProgression.Tier.TIER2));

        // Advance to all tiers phase
        vm.warp(startTime + 5 days);

        allowedTiers = tierProgression.getAllowedTiers();
        assertEq(allowedTiers.length, 3);
        assertEq(uint256(allowedTiers[2]), uint256(CNSTierProgression.Tier.TIER3));
    }

    function testGetSaleTimeline() public {
        uint256 startTime = block.timestamp + 1 days;

        vm.prank(owner);
        tierProgression.startSale(startTime);

        (uint256 returnedStartTime, uint256 tier1EndTime, uint256 tier12EndTime, uint256 allTiersEndTime) =
            tierProgression.getSaleTimeline();

        assertEq(returnedStartTime, startTime);
        assertEq(tier1EndTime, startTime + 1 days);
        assertEq(tier12EndTime, startTime + 3 days);
        assertEq(allTiersEndTime, startTime + 10 days);
    }

    function testEmergencyStop() public {
        uint256 startTime = block.timestamp + 1 days;

        vm.prank(owner);
        tierProgression.startSale(startTime);

        vm.prank(owner);
        tierProgression.emergencyStop();

        assertEq(tierProgression.saleStartTime(), 0);
        assertEq(uint256(tierProgression.getCurrentPhase()), uint256(CNSTierProgression.SalePhase.NOT_STARTED));
    }
}

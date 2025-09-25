// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/CNSAccessControl.sol";

contract CNSAccessControlTest is Test {
    CNSAccessControl public accessControl;

    address public owner = address(0x123);
    address public user1 = address(0x456);
    address public user2 = address(0x789);

    function setUp() public {
        // Fund test accounts
        vm.deal(owner, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        accessControl = new CNSAccessControl(
            owner,
            address(0x111), // Mock NFT contract
            address(0x222) // Mock tier progression
        );
    }

    function testInitialState() public {
        (address nftContract, bool isActive) = accessControl.accessNFT();
        assertEq(nftContract, address(0x111));
        assertEq(isActive, true);
        assertEq(accessControl.tierProgression(), address(0x222));
    }

    function testSetAccessNFT() public {
        address newNFT = address(0x999);

        vm.prank(owner);
        accessControl.setAccessNFT(newNFT, false);

        (address nftContract, bool isActive) = accessControl.accessNFT();
        assertEq(nftContract, newNFT);
        assertEq(isActive, false);
    }

    function testSetTierProgression() public {
        address newProgression = address(0x888);

        vm.prank(owner);
        accessControl.setTierProgression(newProgression);

        assertEq(accessControl.tierProgression(), newProgression);
    }

    function testHasPurchaseAccess() public {
        (bool hasAccess, CNSAccessControl.Tier userTier, CNSAccessControl.SalePhase currentPhase) =
            accessControl.hasPurchaseAccess(user1);

        // Should return false since contracts are not set up properly in test
        assertEq(hasAccess, false);
        assertEq(uint256(userTier), uint256(CNSAccessControl.Tier.NONE));
        assertEq(uint256(currentPhase), uint256(CNSAccessControl.SalePhase.NOT_STARTED));
    }

    function testGetAccessInfo() public {
        (
            bool hasAccess,
            CNSAccessControl.Tier userTier,
            CNSAccessControl.SalePhase currentPhase,
            uint256 timeUntilNextPhase,
            CNSAccessControl.Tier[] memory allowedTiers,
            bool isActive
        ) = accessControl.getAccessInfo(user1);

        assertEq(hasAccess, false);
        assertEq(uint256(userTier), uint256(CNSAccessControl.Tier.NONE));
        assertEq(uint256(currentPhase), uint256(CNSAccessControl.SalePhase.NOT_STARTED));
        assertEq(timeUntilNextPhase, 0);
        assertEq(allowedTiers.length, 0);
        assertEq(isActive, false);
    }

    function testEmergencyDisable() public {
        vm.prank(owner);
        accessControl.emergencyDisable();

        (, bool isActive) = accessControl.accessNFT();
        assertEq(isActive, false);
    }

    function testEmergencyEnable() public {
        vm.prank(owner);
        accessControl.emergencyDisable();

        vm.prank(owner);
        accessControl.emergencyEnable();

        (, bool isActive) = accessControl.accessNFT();
        assertEq(isActive, true);
    }

    function testIsHealthy() public {
        assertEq(accessControl.isHealthy(), false); // Should be false since contracts are mocked

        vm.prank(owner);
        accessControl.setAccessNFT(address(0x123), true);

        vm.prank(owner);
        accessControl.setTierProgression(address(0x456));

        assertEq(accessControl.isHealthy(), true);
    }

    function testGetContractAddresses() public {
        (address nftAddr,) = accessControl.accessNFT();
        address progressionAddr = accessControl.tierProgression();

        assertEq(nftAddr, address(0x111));
        assertEq(progressionAddr, address(0x222));
    }
}

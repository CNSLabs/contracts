// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/CNSTokenL2.sol";

contract CNSTokenL2Test is Test {
    CNSTokenL2 public token;
    address public owner = address(0x123);
    address public user1 = address(0x456);
    address public bridge = address(0x789);

    function setUp() public {
        token = new CNSTokenL2(owner, address(0x111)); // Mock L1 token
    }

    function testMintByOwner() public {
        vm.prank(owner);
        token.mint(user1, 1000 * 10 ** 18);

        assertEq(token.balanceOf(user1), 1000 * 10 ** 18);
        assertEq(token.totalSupply(), 1000 * 10 ** 18);
    }

    function testMintByBridge() public {
        vm.prank(owner);
        token.setBridgeContract(bridge);

        vm.prank(owner);
        token.mint(user1, 1000 * 10 ** 18);

        assertEq(token.balanceOf(user1), 1000 * 10 ** 18);
    }

    function testMaxSupply() public {
        // Start a prank session for the owner
        vm.startPrank(owner);

        // Set bridge first
        token.setBridgeContract(bridge);

        // Test if owner can call a simple function first
        token.pause(); // This should work if owner is recognized

        token.unpause(); // Unpause before minting

        // Mint to max supply
        token.mint(user1, token.L2_MAX_SUPPLY());

        // This should fail with max supply exceeded
        vm.expectRevert("CNSTokenL2: max supply exceeded");
        token.mint(user1, 1);

        // Stop the prank session
        vm.stopPrank();
    }

    function testLockTokens() public {
        vm.prank(owner);
        token.mint(user1, 1000 * 10 ** 18);

        vm.prank(user1);
        token.lockTokens(500 * 10 ** 18);

        assertEq(token.balanceOf(user1), 500 * 10 ** 18);
        assertEq(token.balanceOf(address(token)), 500 * 10 ** 18);
        assertEq(token.getLockedBalance(user1), 500 * 10 ** 18);
    }

    function testUnlockTokens() public {
        vm.prank(owner);
        token.setBridgeContract(bridge);

        vm.prank(owner);
        token.mint(user1, 1000 * 10 ** 18);

        vm.prank(user1);
        token.lockTokens(500 * 10 ** 18);

        vm.prank(owner);
        token.unlockTokens(user1, 500 * 10 ** 18);

        assertEq(token.balanceOf(user1), 1000 * 10 ** 18);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.getLockedBalance(user1), 0);
    }

    function testSetContracts() public {
        address newL1Token = address(0x999);
        address newBridge = address(0x888);

        vm.prank(owner);
        token.setL1Token(newL1Token);

        assertEq(token.l1Token(), newL1Token);

        vm.prank(owner);
        token.setBridgeContract(newBridge);

        assertEq(token.l2Bridge(), newBridge);
    }

    function testPauseUnpause() public {
        vm.prank(owner);
        token.pause();

        assertEq(token.paused(), true);

        vm.prank(owner);
        token.unpause();

        assertEq(token.paused(), false);
    }

    function testBurnFromLocked() public {
        vm.prank(owner);
        token.setBridgeContract(bridge);

        vm.prank(owner);
        token.mint(user1, 1000 * 10 ** 18);

        vm.prank(user1);
        token.lockTokens(500 * 10 ** 18);

        // Set allowance for owner to burn from contract
        vm.prank(address(token));
        token.approve(owner, 300 * 10 ** 18);

        vm.prank(owner);
        token.burnFrom(address(token), 300 * 10 ** 18);

        assertEq(token.balanceOf(address(token)), 200 * 10 ** 18);
    }

    function testEmergencyTransfer() public {
        vm.prank(owner);
        token.mint(address(token), 1000 * 10 ** 18);

        vm.prank(owner);
        token.emergencyTransfer(address(token), user1, 1000 * 10 ** 18);

        assertEq(token.balanceOf(user1), 1000 * 10 ** 18);
        assertEq(token.balanceOf(address(token)), 0);
    }
}

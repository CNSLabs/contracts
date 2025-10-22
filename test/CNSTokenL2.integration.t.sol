// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {CNSTokenL2} from "../src/CNSTokenL2.sol";
import {CNSTokenL2V2} from "../src/CNSTokenL2V2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Mock bridge contract for testing
contract MockBridge {
    // Empty contract that just needs to exist

    }

/**
 * @title CNSTokenL2 Integration Tests
 * @dev Multi-step workflow tests for CNSTokenL2 contract
 * @notice Tests complex scenarios involving multiple operations and state changes
 */
contract CNSTokenL2IntegrationTest is Test {
    CNSTokenL2 internal token;
    MockBridge internal bridge;
    address internal admin;
    address internal l1Token;
    address internal user1;
    address internal user2;
    address internal user3;

    string constant NAME = "CNS Token L2";
    string constant SYMBOL = "CNS";
    uint8 constant DECIMALS = 18;

    function setUp() public {
        admin = makeAddr("admin");
        bridge = new MockBridge();
        l1Token = makeAddr("l1Token");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        token = _deployInitializedProxy(admin, admin, admin, admin, address(bridge), l1Token);
    }

    function _deployInitializedProxy(
        address defaultAdmin_,
        address upgrader_,
        address pauser_,
        address allowlistAdmin_,
        address bridge_,
        address l1Token_
    ) internal returns (CNSTokenL2) {
        CNSTokenL2 implementation = new CNSTokenL2();
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
        CNSTokenL2 proxied = CNSTokenL2(address(proxy));
        proxied.initialize(
            defaultAdmin_, upgrader_, pauser_, allowlistAdmin_, bridge_, l1Token_, NAME, SYMBOL, DECIMALS
        );
        return proxied;
    }

    // ============ Bridge Integration Tests ============

    function testCompleteBridgeWorkflow() public {
        // Step 1: Bridge mints tokens to user1
        vm.prank(address(bridge));
        token.mint(user1, 1000 ether);

        assertEq(token.balanceOf(user1), 1000 ether);
        assertEq(token.totalSupply(), 1000 ether);

        // Step 2: Admin allowlists user1
        vm.prank(admin);
        token.setSenderAllowed(user1, true);

        assertTrue(token.isSenderAllowlisted(user1));

        // Step 3: user1 transfers tokens to user2
        vm.prank(user1);
        token.transfer(user2, 500 ether);

        assertEq(token.balanceOf(user1), 500 ether);
        assertEq(token.balanceOf(user2), 500 ether);

        // Step 4: user2 approves bridge to burn tokens
        vm.prank(user2);
        token.approve(address(bridge), 300 ether);

        assertEq(token.allowance(user2, address(bridge)), 300 ether);

        // Step 5: Bridge burns tokens from user2
        vm.prank(address(bridge));
        token.burn(user2, 300 ether);

        assertEq(token.balanceOf(user2), 200 ether);
        assertEq(token.totalSupply(), 700 ether);
    }

    function testMultiUserBridgeWorkflow() public {
        // Step 1: Bridge mints to multiple users
        vm.prank(address(bridge));
        token.mint(user1, 1000 ether);

        vm.prank(address(bridge));
        token.mint(user2, 2000 ether);

        vm.prank(address(bridge));
        token.mint(user3, 1500 ether);

        assertEq(token.totalSupply(), 4500 ether);

        // Step 2: Admin batch allowlists users
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        vm.prank(admin);
        token.setSenderAllowedBatch(users, true);

        assertTrue(token.isSenderAllowlisted(user1));
        assertTrue(token.isSenderAllowlisted(user2));
        assertTrue(token.isSenderAllowlisted(user3));

        // Step 3: Users transfer tokens among themselves
        vm.prank(user1);
        token.transfer(user2, 200 ether);

        vm.prank(user2);
        token.transfer(user3, 500 ether);

        vm.prank(user3);
        token.transfer(user1, 300 ether);

        // Step 4: Verify final balances
        assertEq(token.balanceOf(user1), 1100 ether); // 1000 - 200 + 300
        assertEq(token.balanceOf(user2), 1700 ether); // 2000 + 200 - 500
        assertEq(token.balanceOf(user3), 1700 ether); // 1500 + 500 - 300
        assertEq(token.totalSupply(), 4500 ether); // Unchanged
    }

    // ============ Pause Integration Tests ============

    function testPauseUnpauseWorkflow() public {
        // Step 1: Set up initial state
        vm.prank(address(bridge));
        token.mint(user1, 1000 ether);

        vm.prank(admin);
        token.setSenderAllowed(user1, true);

        // Step 2: Verify normal operation
        vm.prank(user1);
        token.transfer(user2, 100 ether);

        assertEq(token.balanceOf(user2), 100 ether);

        // Step 3: Pause the contract
        vm.prank(admin);
        token.pause();

        assertTrue(token.paused());

        // Step 4: Verify transfers are blocked
        vm.prank(user1);
        vm.expectRevert();
        token.transfer(user2, 100 ether);

        // Step 5: Verify minting is also blocked
        vm.prank(address(bridge));
        vm.expectRevert();
        token.mint(user3, 500 ether);

        // Step 6: Unpause the contract
        vm.prank(admin);
        token.unpause();

        assertFalse(token.paused());

        // Step 7: Verify normal operation resumes
        vm.prank(user1);
        token.transfer(user2, 100 ether);

        assertEq(token.balanceOf(user2), 200 ether);

        vm.prank(address(bridge));
        token.mint(user3, 500 ether);

        assertEq(token.balanceOf(user3), 500 ether);
    }

    function testEmergencyPauseScenario() public {
        // Step 1: Set up normal operation
        vm.prank(address(bridge));
        token.mint(user1, 1000 ether);

        vm.prank(admin);
        token.setSenderAllowed(user1, true);

        // Step 2: Simulate emergency - pause immediately
        vm.prank(admin);
        token.pause();

        // Step 3: Verify all operations are blocked
        vm.prank(user1);
        vm.expectRevert();
        token.transfer(user2, 100 ether);

        vm.prank(address(bridge));
        vm.expectRevert();
        token.mint(user2, 100 ether);

        vm.prank(user1);
        token.approve(address(bridge), 100 ether);

        vm.prank(address(bridge));
        vm.expectRevert();
        token.burn(user1, 100 ether);

        // Step 4: Verify state is preserved
        assertEq(token.balanceOf(user1), 1000 ether);
        assertEq(token.totalSupply(), 1000 ether);
        assertTrue(token.isSenderAllowlisted(user1));
    }

    // ============ Role Management Integration Tests ============

    function testRoleDelegationWorkflow() public {
        // Test role-based operations using roles assigned during initialization
        // Admin has PAUSER_ROLE, so can pause/unpause
        vm.prank(admin);
        token.pause();
        assertTrue(token.paused(), "Admin should be able to pause");

        vm.prank(admin);
        token.unpause();
        assertFalse(token.paused(), "Admin should be able to unpause");

        // Admin has ALLOWLIST_ADMIN_ROLE, so can manage allowlist
        vm.prank(admin);
        token.setSenderAllowed(user1, true);
        assertTrue(token.isSenderAllowlisted(user1), "Admin should be able to allowlist users");

        vm.prank(admin);
        token.setSenderAllowed(user1, false);
        assertFalse(token.isSenderAllowlisted(user1), "Admin should be able to remove users from allowlist");

        // Verify admin has all required roles
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin), "Admin should have DEFAULT_ADMIN_ROLE");
        assertTrue(token.hasRole(token.PAUSER_ROLE(), admin), "Admin should have PAUSER_ROLE");
        assertTrue(token.hasRole(token.ALLOWLIST_ADMIN_ROLE(), admin), "Admin should have ALLOWLIST_ADMIN_ROLE");
        assertTrue(token.hasRole(token.UPGRADER_ROLE(), admin), "Admin should have UPGRADER_ROLE");
    }

    function testMultiRoleManagement() public {
        // Test that admin can perform operations requiring different roles
        // Admin has PAUSER_ROLE - test pause functionality
        vm.prank(admin);
        token.pause();
        assertTrue(token.paused(), "Admin should be able to pause");

        vm.prank(admin);
        token.unpause();
        assertFalse(token.paused(), "Admin should be able to unpause");

        // Admin has ALLOWLIST_ADMIN_ROLE - test allowlist management
        vm.prank(admin);
        token.setSenderAllowed(user1, true);
        assertTrue(token.isSenderAllowlisted(user1), "Admin should be able to allowlist user1");

        vm.prank(admin);
        token.setSenderAllowed(user2, true);
        assertTrue(token.isSenderAllowlisted(user2), "Admin should be able to allowlist user2");

        // Test batch allowlist operations
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        vm.prank(admin);
        token.setSenderAllowedBatch(users, false);
        assertFalse(token.isSenderAllowlisted(user1), "Batch operation should remove user1 from allowlist");
        assertFalse(token.isSenderAllowlisted(user2), "Batch operation should remove user2 from allowlist");

        // Verify role assignments are correct
        assertTrue(token.hasRole(token.PAUSER_ROLE(), admin), "Admin should have PAUSER_ROLE");
        assertTrue(token.hasRole(token.ALLOWLIST_ADMIN_ROLE(), admin), "Admin should have ALLOWLIST_ADMIN_ROLE");
        assertFalse(token.hasRole(token.PAUSER_ROLE(), user1), "User1 should not have PAUSER_ROLE");
        assertFalse(token.hasRole(token.ALLOWLIST_ADMIN_ROLE(), user2), "User2 should not have ALLOWLIST_ADMIN_ROLE");
    }

    // ============ Upgrade Integration Tests ============

    function testUpgradeWorkflow() public {
        // Step 1: Set up initial state
        vm.prank(address(bridge));
        token.mint(user1, 1000 ether);

        vm.prank(admin);
        token.setSenderAllowed(user1, true);

        vm.prank(user1);
        token.transfer(user2, 200 ether);

        // Step 2: Verify current state
        assertEq(token.balanceOf(user1), 800 ether);
        assertEq(token.balanceOf(user2), 200 ether);
        assertEq(token.totalSupply(), 1000 ether);
        assertTrue(token.isSenderAllowlisted(user1));
        assertEq(token.version(), "1.0.0");

        // Step 3: Deploy new implementation
        CNSTokenL2V2 newImpl = new CNSTokenL2V2();

        // Step 4: Upgrade to V2
        vm.prank(admin);
        token.upgradeToAndCall(address(newImpl), "");

        // Step 5: Verify state is preserved
        assertEq(token.balanceOf(user1), 800 ether);
        assertEq(token.balanceOf(user2), 200 ether);
        assertEq(token.totalSupply(), 1000 ether);
        assertTrue(token.isSenderAllowlisted(user1));

        // Step 6: Verify version updated
        assertEq(token.version(), "2.0.0");

        // Step 7: Verify V2 functionality works
        vm.prank(user1);
        token.transfer(user2, 100 ether);

        assertEq(token.balanceOf(user1), 700 ether);
        assertEq(token.balanceOf(user2), 300 ether);
    }

    function testUpgradeWithComplexState() public {
        // Step 1: Set up complex state
        vm.prank(address(bridge));
        token.mint(user1, 1000 ether);

        vm.prank(address(bridge));
        token.mint(user2, 2000 ether);

        vm.prank(admin);
        token.setSenderAllowed(user1, true);

        vm.prank(admin);
        token.setSenderAllowed(user2, true);

        vm.prank(user1);
        token.approve(user2, 500 ether);

        vm.prank(user2);
        token.transferFrom(user1, user2, 300 ether);

        // Step 2: Pause the contract
        vm.prank(admin);
        token.pause();

        // Step 3: Upgrade while paused
        CNSTokenL2V2 newImpl = new CNSTokenL2V2();

        vm.prank(admin);
        token.upgradeToAndCall(address(newImpl), "");

        // Step 4: Verify all state is preserved
        assertEq(token.balanceOf(user1), 700 ether);
        assertEq(token.balanceOf(user2), 2300 ether);
        assertEq(token.totalSupply(), 3000 ether);
        assertTrue(token.isSenderAllowlisted(user1));
        assertTrue(token.isSenderAllowlisted(user2));
        assertTrue(token.paused());
        assertEq(token.version(), "2.0.0");

        // Step 5: Unpause and verify functionality
        vm.prank(admin);
        token.unpause();

        vm.prank(user1);
        token.transfer(user2, 100 ether);

        assertEq(token.balanceOf(user1), 600 ether);
        assertEq(token.balanceOf(user2), 2400 ether);
    }

    // ============ Allowlist Integration Tests ============

    function testAllowlistToggleWorkflow() public {
        // Step 1: Mint tokens to user1
        vm.prank(address(bridge));
        token.mint(user1, 1000 ether);

        // Step 2: user1 cannot transfer (not allowlisted)
        vm.prank(user1);
        vm.expectRevert(CNSTokenL2.SenderNotAllowlisted.selector);
        token.transfer(user2, 100 ether);

        // Step 3: Admin allowlists user1
        vm.prank(admin);
        token.setSenderAllowed(user1, true);

        // Step 4: user1 can now transfer
        vm.prank(user1);
        token.transfer(user2, 100 ether);

        assertEq(token.balanceOf(user2), 100 ether);

        // Step 5: Admin removes user1 from allowlist
        vm.prank(admin);
        token.setSenderAllowed(user1, false); // Set to false

        // Step 6: user1 cannot transfer anymore
        vm.prank(user1);
        vm.expectRevert(CNSTokenL2.SenderNotAllowlisted.selector);
        token.transfer(user2, 100 ether);

        // Step 7: But user2 can transfer (if allowlisted)
        vm.prank(admin);
        token.setSenderAllowed(user2, true);

        vm.prank(user2);
        token.transfer(user1, 50 ether);

        assertEq(token.balanceOf(user1), 950 ether);
        assertEq(token.balanceOf(user2), 50 ether);
    }

    function testAllowlistBatchManagement() public {
        // Step 1: Mint tokens to multiple users
        vm.prank(address(bridge));
        token.mint(user1, 1000 ether);

        vm.prank(address(bridge));
        token.mint(user2, 1000 ether);

        vm.prank(address(bridge));
        token.mint(user3, 1000 ether);

        // Step 2: Batch allowlist all users
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        vm.prank(admin);
        token.setSenderAllowedBatch(users, true);

        // Step 3: All users can now transfer
        vm.prank(user1);
        token.transfer(user2, 100 ether);

        vm.prank(user2);
        token.transfer(user3, 100 ether);

        vm.prank(user3);
        token.transfer(user1, 100 ether);

        // Step 4: Verify final balances
        assertEq(token.balanceOf(user1), 1000 ether); // 1000 - 100 + 100
        assertEq(token.balanceOf(user2), 1000 ether); // 1000 + 100 - 100
        assertEq(token.balanceOf(user3), 1000 ether); // 1000 + 100 - 100

        // Step 5: Batch remove from allowlist
        vm.prank(admin);
        token.setSenderAllowedBatch(users, false);

        // Step 6: No one can transfer anymore
        vm.prank(user1);
        vm.expectRevert(CNSTokenL2.SenderNotAllowlisted.selector);
        token.transfer(user2, 100 ether);
    }

    // ============ Complex Multi-Step Workflows ============

    function testCompleteTokenLifecycle() public {
        // Step 1: Initial minting
        vm.prank(address(bridge));
        token.mint(user1, 1000 ether);

        assertEq(token.totalSupply(), 1000 ether);

        // Step 2: Allowlist management
        vm.prank(admin);
        token.setSenderAllowed(user1, true);
        vm.prank(admin);
        token.setSenderAllowed(user2, true);
        vm.prank(admin);
        token.setSenderAllowed(user3, true);

        // Step 3: User transfers
        vm.prank(user1);
        token.transfer(user2, 300 ether);

        vm.prank(user1);
        token.transfer(user3, 200 ether);

        // Step 4: Approval and transferFrom
        vm.prank(user2);
        token.approve(user3, 150 ether);

        vm.prank(user3);
        token.transferFrom(user2, user1, 150 ether);

        // Step 5: More minting
        vm.prank(address(bridge));
        token.mint(user2, 500 ether);

        // Step 6: Pause and unpause
        vm.prank(admin);
        token.pause();

        vm.prank(admin);
        token.unpause();

        // Step 7: Final transfers
        vm.prank(user1);
        token.transfer(user3, 100 ether);

        // Step 8: Burn tokens
        vm.prank(user3);
        token.approve(address(bridge), 200 ether);

        vm.prank(address(bridge));
        token.burn(user3, 200 ether);

        // Step 9: Verify final state
        assertEq(token.balanceOf(user1), 550 ether); // 1000 - 300 - 200 + 150 - 100
        assertEq(token.balanceOf(user2), 650 ether); // 300 - 150 + 500
        assertEq(token.balanceOf(user3), 100 ether); // 200 + 150 + 100 - 200
        assertEq(token.totalSupply(), 1300 ether); // 1000 + 500 - 200
    }

    function testEmergencyRecoveryScenario() public {
        // Step 1: Set up normal operation
        vm.prank(address(bridge));
        token.mint(user1, 1000 ether);

        vm.prank(admin);
        token.setSenderAllowed(user1, true);

        vm.prank(user1);
        token.transfer(user2, 200 ether);

        // Step 2: Simulate emergency - pause everything
        vm.prank(admin);
        token.pause();

        // Step 3: Verify all operations are blocked
        vm.prank(user1);
        vm.expectRevert();
        token.transfer(user2, 100 ether);

        vm.prank(address(bridge));
        vm.expectRevert();
        token.mint(user3, 500 ether);

        // Step 4: Emergency recovery - unpause
        vm.prank(admin);
        token.unpause();

        // Step 5: Verify normal operation resumes
        vm.prank(user1);
        token.transfer(user2, 100 ether);

        assertEq(token.balanceOf(user2), 300 ether);

        vm.prank(address(bridge));
        token.mint(user3, 500 ether);

        assertEq(token.balanceOf(user3), 500 ether);

        // Step 6: Verify final state
        assertEq(token.balanceOf(user1), 700 ether);
        assertEq(token.totalSupply(), 1500 ether);
    }
}

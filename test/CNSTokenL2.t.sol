// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {CNSTokenL2} from "../src/CNSTokenL2.sol";

contract CNSTokenL2Test is Test {
    CNSTokenL2 internal token;

    address internal admin;
    address internal bridge;
    address internal l1Token;
    address internal user1;
    address internal user2;

    uint8 internal constant DECIMALS = 18;
    uint256 internal constant INITIAL_BRIDGE_MINT = 1_000 ether;

    string internal constant NAME = "CNS Linea Token";
    string internal constant SYMBOL = "CNSL";

    // Role constants
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 internal constant ALLOWLIST_ADMIN_ROLE = keccak256("ALLOWLIST_ADMIN_ROLE");
    bytes32 internal constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    function setUp() public {
        admin = makeAddr("admin");
        // Deploy a mock bridge contract
        MockBridge mockBridge = new MockBridge();
        bridge = address(mockBridge);
        l1Token = makeAddr("l1Token");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        token = _deployInitializedProxy(admin, admin, admin, bridge, l1Token);
    }

    function _deployInitializedProxy(
        address multisig_,
        address pauser_,
        address allowlistAdmin_,
        address bridge_,
        address l1Token_
    ) internal returns (CNSTokenL2) {
        CNSTokenL2 implementation = new CNSTokenL2();
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
        CNSTokenL2 proxied = CNSTokenL2(address(proxy));
        proxied.initialize(multisig_, pauser_, allowlistAdmin_, bridge_, l1Token_, NAME, SYMBOL, DECIMALS);
        return proxied;
    }

    function testInitializeSetsState() public view {
        assertEq(token.bridge(), bridge);
        assertEq(token.l1Token(), l1Token);
        assertEq(token.name(), NAME);
        assertEq(token.symbol(), SYMBOL);
        assertEq(token.decimals(), DECIMALS);

        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.PAUSER_ROLE(), admin));
        assertTrue(token.hasRole(token.ALLOWLIST_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.UPGRADER_ROLE(), admin));

        assertTrue(token.senderAllowlistEnabled());
        assertTrue(token.isSenderAllowlisted(address(token)));
        assertTrue(token.isSenderAllowlisted(bridge));
        assertTrue(token.isSenderAllowlisted(admin));
    }

    function testInitializeRevertsOnZeroAddresses() public {
        CNSTokenL2 fresh = _deployProxy();

        vm.expectRevert("multisig=0");
        fresh.initialize(address(0), admin, admin, bridge, l1Token, NAME, SYMBOL, DECIMALS);

        fresh = _deployProxy();
        vm.expectRevert("pauser=0");
        fresh.initialize(admin, address(0), admin, bridge, l1Token, NAME, SYMBOL, DECIMALS);

        fresh = _deployProxy();
        vm.expectRevert("allowlistAdmin=0");
        fresh.initialize(admin, admin, address(0), bridge, l1Token, NAME, SYMBOL, DECIMALS);

        fresh = _deployProxy();
        vm.expectRevert("bridge=0");
        fresh.initialize(admin, admin, admin, address(0), l1Token, NAME, SYMBOL, DECIMALS);

        fresh = _deployProxy();
        vm.expectRevert("l1Token=0");
        fresh.initialize(admin, admin, admin, bridge, address(0), NAME, SYMBOL, DECIMALS);
    }

    function testInitializeCannotRunTwice() public {
        vm.expectRevert();
        token.initialize(admin, admin, admin, bridge, l1Token, NAME, SYMBOL, DECIMALS);
    }

    function testBridgeMintBypassesAllowlist() public {
        vm.prank(bridge);
        token.mint(user1, INITIAL_BRIDGE_MINT);

        assertEq(token.balanceOf(user1), INITIAL_BRIDGE_MINT);

        vm.prank(user1);
        vm.expectRevert("sender not allowlisted");
        token.transfer(user2, 1 ether);
    }

    function testAllowlistAdminCanEnableTransfers() public {
        vm.prank(bridge);
        token.mint(user1, INITIAL_BRIDGE_MINT);

        vm.prank(admin);
        token.setSenderAllowed(user1, true);

        vm.prank(user1);
        token.transfer(user2, 100 ether);

        assertEq(token.balanceOf(user2), 100 ether);
    }

    function testPauseBlocksTransfers() public {
        vm.prank(bridge);
        token.mint(user1, INITIAL_BRIDGE_MINT);

        vm.prank(admin);
        token.setSenderAllowed(user1, true);

        vm.prank(admin);
        token.pause();

        vm.prank(user1);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        token.transfer(user2, 1 ether);

        vm.prank(admin);
        token.unpause();

        vm.prank(user1);
        token.transfer(user2, 1 ether);
        assertEq(token.balanceOf(user2), 1 ether);
    }

    function testBridgeBurnHonorsAllowance() public {
        vm.prank(bridge);
        token.mint(user1, INITIAL_BRIDGE_MINT);

        vm.prank(admin);
        token.setSenderAllowed(user1, true);

        vm.prank(user1);
        token.approve(bridge, INITIAL_BRIDGE_MINT);

        vm.prank(bridge);
        token.burn(user1, INITIAL_BRIDGE_MINT);

        assertEq(token.balanceOf(user1), 0);
        assertEq(token.totalSupply(), 0);
    }

    function testDisableSenderAllowlist() public {
        vm.prank(bridge);
        token.mint(user1, INITIAL_BRIDGE_MINT);

        // user1 is not allowlisted, transfer should fail
        vm.prank(user1);
        vm.expectRevert("sender not allowlisted");
        token.transfer(user2, 1 ether);

        // Disable sender allowlist
        vm.prank(admin);
        token.setSenderAllowlistEnabled(false);

        // Now transfer should work without allowlist
        vm.prank(user1);
        token.transfer(user2, 1 ether);
        assertEq(token.balanceOf(user2), 1 ether);

        // Re-enable allowlist
        vm.prank(admin);
        token.setSenderAllowlistEnabled(true);

        // Transfer should fail again
        vm.prank(user1);
        vm.expectRevert("sender not allowlisted");
        token.transfer(user2, 1 ether);
    }

    function testAllowlistOnlyAppliesToSenderNotRecipient() public {
        vm.prank(bridge);
        token.mint(user1, INITIAL_BRIDGE_MINT);

        // Allowlist user1 as sender only
        vm.prank(admin);
        token.setSenderAllowed(user1, true);

        // user2 is NOT allowlisted as sender
        assertFalse(token.isSenderAllowlisted(user2));

        // Transfer FROM user1 (allowlisted) TO user2 (not allowlisted) - should succeed
        vm.prank(user1);
        token.transfer(user2, 100 ether);
        assertEq(token.balanceOf(user2), 100 ether);

        // Now try transfer FROM user2 (not allowlisted) TO user1 (allowlisted) - should fail
        vm.prank(user2);
        vm.expectRevert("sender not allowlisted");
        token.transfer(user1, 50 ether);

        // Verify user2's balance is unchanged
        assertEq(token.balanceOf(user2), 100 ether);
    }

    function testUpgradeByUpgraderSucceeds() public {
        CNSTokenL2MockV2 newImplementation = new CNSTokenL2MockV2();

        vm.prank(admin);
        token.upgradeToAndCall(address(newImplementation), "");

        CNSTokenL2MockV2 upgraded = CNSTokenL2MockV2(address(token));

        assertEq(upgraded.version(), 2);
        assertEq(upgraded.bridge(), bridge);
        assertTrue(upgraded.hasRole(upgraded.UPGRADER_ROLE(), admin));
    }

    function testUpgradeByNonUpgraderReverts() public {
        CNSTokenL2MockV2 newImplementation = new CNSTokenL2MockV2();

        vm.expectRevert(
            abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", user1, token.UPGRADER_ROLE())
        );
        vm.prank(user1);
        token.upgradeToAndCall(address(newImplementation), "");
    }

    function _deployProxy() internal returns (CNSTokenL2) {
        CNSTokenL2 implementation = new CNSTokenL2();
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
        return CNSTokenL2(address(proxy));
    }

    // ============ Role Separation Tests ============

    function testRoleSeparationMultisigHasCriticalRoles() public {
        address multisig = makeAddr("multisig");
        address pauser = makeAddr("pauser");
        address allowlistAdmin = makeAddr("allowlistAdmin");

        CNSTokenL2 separatedToken = _deployInitializedProxy(multisig, pauser, allowlistAdmin, bridge, l1Token);

        // Multisig should have critical roles
        assertTrue(separatedToken.hasRole(DEFAULT_ADMIN_ROLE, multisig));
        assertTrue(separatedToken.hasRole(UPGRADER_ROLE, multisig));
    }

    function testRoleSeparationOperationalRolesAssigned() public {
        address multisig = makeAddr("multisig");
        address pauser = makeAddr("pauser");
        address allowlistAdmin = makeAddr("allowlistAdmin");

        CNSTokenL2 separatedToken = _deployInitializedProxy(multisig, pauser, allowlistAdmin, bridge, l1Token);

        // Operational roles should be assigned to dedicated addresses
        assertTrue(separatedToken.hasRole(PAUSER_ROLE, pauser));
        assertTrue(separatedToken.hasRole(ALLOWLIST_ADMIN_ROLE, allowlistAdmin));

        // Multisig should also have operational roles as backup
        assertTrue(separatedToken.hasRole(PAUSER_ROLE, multisig));
        assertTrue(separatedToken.hasRole(ALLOWLIST_ADMIN_ROLE, multisig));
    }

    function testRoleSeparationPauserCanPause() public {
        address multisig = makeAddr("multisig");
        address pauser = makeAddr("pauser");
        address allowlistAdmin = makeAddr("allowlistAdmin");

        CNSTokenL2 separatedToken = _deployInitializedProxy(multisig, pauser, allowlistAdmin, bridge, l1Token);

        // Pauser should be able to pause
        vm.prank(pauser);
        separatedToken.pause();
        assertTrue(separatedToken.paused());

        // Pauser should be able to unpause
        vm.prank(pauser);
        separatedToken.unpause();
        assertFalse(separatedToken.paused());
    }

    function testRoleSeparationAllowlistAdminCanManageAllowlist() public {
        address multisig = makeAddr("multisig");
        address pauser = makeAddr("pauser");
        address allowlistAdmin = makeAddr("allowlistAdmin");
        address testUser = makeAddr("testUser");

        CNSTokenL2 separatedToken = _deployInitializedProxy(multisig, pauser, allowlistAdmin, bridge, l1Token);

        // Allowlist admin should be able to manage allowlist
        vm.prank(allowlistAdmin);
        separatedToken.setSenderAllowed(testUser, true);
        assertTrue(separatedToken.isSenderAllowlisted(testUser));

        vm.prank(allowlistAdmin);
        separatedToken.setSenderAllowed(testUser, false);
        assertFalse(separatedToken.isSenderAllowlisted(testUser));
    }

    function testRoleSeparationOnlyMultisigCanUpgrade() public {
        address multisig = makeAddr("multisig");
        address pauser = makeAddr("pauser");
        address allowlistAdmin = makeAddr("allowlistAdmin");

        CNSTokenL2 separatedToken = _deployInitializedProxy(multisig, pauser, allowlistAdmin, bridge, l1Token);
        CNSTokenL2MockV2 newImpl = new CNSTokenL2MockV2();

        // Multisig can upgrade
        vm.prank(multisig);
        separatedToken.upgradeToAndCall(address(newImpl), "");

        // Pauser cannot upgrade
        CNSTokenL2 separatedToken2 = _deployInitializedProxy(multisig, pauser, allowlistAdmin, bridge, l1Token);
        vm.prank(pauser);
        vm.expectRevert();
        separatedToken2.upgradeToAndCall(address(newImpl), "");

        // Allowlist admin cannot upgrade
        CNSTokenL2 separatedToken3 = _deployInitializedProxy(multisig, pauser, allowlistAdmin, bridge, l1Token);
        vm.prank(allowlistAdmin);
        vm.expectRevert();
        separatedToken3.upgradeToAndCall(address(newImpl), "");
    }

    function testRoleSeparationMultisigAsBackupCanPause() public {
        address multisig = makeAddr("multisig");
        address pauser = makeAddr("pauser");
        address allowlistAdmin = makeAddr("allowlistAdmin");

        CNSTokenL2 separatedToken = _deployInitializedProxy(multisig, pauser, allowlistAdmin, bridge, l1Token);

        // Multisig as backup can pause
        vm.prank(multisig);
        separatedToken.pause();
        assertTrue(separatedToken.paused());
    }

    function testRoleSeparationMultisigAsBackupCanManageAllowlist() public {
        address multisig = makeAddr("multisig");
        address pauser = makeAddr("pauser");
        address allowlistAdmin = makeAddr("allowlistAdmin");
        address testUser = makeAddr("testUser");

        CNSTokenL2 separatedToken = _deployInitializedProxy(multisig, pauser, allowlistAdmin, bridge, l1Token);

        // Multisig as backup can manage allowlist
        vm.prank(multisig);
        separatedToken.setSenderAllowed(testUser, true);
        assertTrue(separatedToken.isSenderAllowlisted(testUser));
    }
}

contract CNSTokenL2MockV2 is CNSTokenL2 {
    function version() external pure returns (uint256) {
        return 2;
    }
}

// Mock bridge contract for testing
contract MockBridge {
    // Empty contract that just needs to exist

    }

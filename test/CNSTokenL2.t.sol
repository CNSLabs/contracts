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

        token = _deployInitializedProxy(admin, admin, admin, admin, bridge, l1Token);
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
        address[] memory emptyAllowlist = new address[](0);
        proxied.initialize(
            defaultAdmin_,
            upgrader_,
            pauser_,
            allowlistAdmin_,
            bridge_,
            l1Token_,
            NAME,
            SYMBOL,
            DECIMALS,
            emptyAllowlist
        );
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
        MockBridge mockBridge = new MockBridge();
        address[] memory emptyAllowlist = new address[](0);

        vm.expectRevert("defaultAdmin=0");
        fresh.initialize(
            address(0), admin, admin, admin, address(mockBridge), l1Token, NAME, SYMBOL, DECIMALS, emptyAllowlist
        );

        fresh = _deployProxy();
        vm.expectRevert("upgrader=0");
        fresh.initialize(
            admin, address(0), admin, admin, address(mockBridge), l1Token, NAME, SYMBOL, DECIMALS, emptyAllowlist
        );

        fresh = _deployProxy();
        vm.expectRevert("pauser=0");
        fresh.initialize(
            admin, admin, address(0), admin, address(mockBridge), l1Token, NAME, SYMBOL, DECIMALS, emptyAllowlist
        );

        fresh = _deployProxy();
        vm.expectRevert("allowlistAdmin=0");
        fresh.initialize(
            admin, admin, admin, address(0), address(mockBridge), l1Token, NAME, SYMBOL, DECIMALS, emptyAllowlist
        );

        fresh = _deployProxy();
        vm.expectRevert("bridge=0");
        fresh.initialize(admin, admin, admin, admin, address(0), l1Token, NAME, SYMBOL, DECIMALS, emptyAllowlist);

        fresh = _deployProxy();
        vm.expectRevert("l1Token=0");
        fresh.initialize(
            admin, admin, admin, admin, address(mockBridge), address(0), NAME, SYMBOL, DECIMALS, emptyAllowlist
        );
    }

    function testInitializeCannotRunTwice() public {
        address[] memory emptyAllowlist = new address[](0);
        vm.expectRevert();
        token.initialize(admin, admin, admin, admin, bridge, l1Token, NAME, SYMBOL, DECIMALS, emptyAllowlist);
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

        assertEq(upgraded.version(), "2.0.0");
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

    function testInitializeRevertsIfBridgeIsEOA() public {
        CNSTokenL2 fresh = _deployProxy();
        address eoa = makeAddr("eoa");
        address[] memory emptyAllowlist = new address[](0);

        vm.expectRevert("bridge must be contract");
        fresh.initialize(admin, admin, admin, admin, eoa, l1Token, NAME, SYMBOL, DECIMALS, emptyAllowlist);
    }

    function testInitializationEmitsEvents() public {
        CNSTokenL2 impl = new CNSTokenL2();
        MockBridge mockBridge = new MockBridge();
        address testBridge = address(mockBridge);
        address[] memory emptyAllowlist = new address[](0);

        bytes memory initData = abi.encodeWithSelector(
            CNSTokenL2.initialize.selector,
            admin,
            admin,
            admin,
            admin,
            testBridge,
            l1Token,
            NAME,
            SYMBOL,
            DECIMALS,
            emptyAllowlist
        );

        vm.expectEmit(true, true, true, true);
        emit CNSTokenL2.Initialized(admin, testBridge, l1Token, NAME, SYMBOL, DECIMALS);

        new ERC1967Proxy(address(impl), initData);
    }

    function testBatchAllowlistRevertsIfTooLarge() public {
        address[] memory accounts = new address[](300);
        for (uint256 i = 0; i < 300; i++) {
            accounts[i] = address(uint160(i + 1));
        }

        vm.prank(admin);
        vm.expectRevert("batch too large");
        token.setSenderAllowedBatch(accounts, true);
    }

    function testBatchAllowlistSucceedsWithinLimit() public {
        address[] memory accounts = new address[](200);
        for (uint256 i = 0; i < 200; i++) {
            accounts[i] = address(uint160(i + 1));
        }

        vm.prank(admin);
        token.setSenderAllowedBatch(accounts, true);

        // Verify first and last were added
        assertTrue(token.isSenderAllowlisted(accounts[0]));
        assertTrue(token.isSenderAllowlisted(accounts[199]));
    }

    function testBatchRevertsIfEmpty() public {
        address[] memory accounts = new address[](0);

        vm.expectRevert("empty batch");
        vm.prank(admin);
        token.setSenderAllowedBatch(accounts, true);
    }

    function testCannotAllowlistZeroAddress() public {
        vm.expectRevert("zero address");
        vm.prank(admin);
        token.setSenderAllowed(address(0), true);
    }

    function testBatchCannotIncludeZeroAddress() public {
        address[] memory accounts = new address[](3);
        accounts[0] = makeAddr("user1");
        accounts[1] = address(0); // Zero address in middle
        accounts[2] = makeAddr("user2");

        vm.expectRevert("zero address");
        vm.prank(admin);
        token.setSenderAllowedBatch(accounts, true);

        // Verify none were added (transaction reverted)
        assertFalse(token.isSenderAllowlisted(accounts[0]));
        assertFalse(token.isSenderAllowlisted(accounts[2]));
    }

    function testAtomicInitializationPreventsReinitialization() public {
        // This verifies the deployment script pattern works
        CNSTokenL2 impl = new CNSTokenL2();
        MockBridge mockBridge = new MockBridge();
        address[] memory emptyAllowlist = new address[](0);

        bytes memory initData = abi.encodeWithSelector(
            CNSTokenL2.initialize.selector,
            admin,
            admin,
            admin,
            admin,
            address(mockBridge),
            l1Token,
            NAME,
            SYMBOL,
            DECIMALS,
            emptyAllowlist
        );

        // Deploy with atomic initialization
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        CNSTokenL2 deployedToken = CNSTokenL2(address(proxy));

        // Verify already initialized
        assertTrue(deployedToken.hasRole(deployedToken.DEFAULT_ADMIN_ROLE(), admin));

        // Cannot initialize again
        vm.expectRevert();
        address[] memory emptyAllowlist2 = new address[](0);
        deployedToken.initialize(
            admin, admin, admin, admin, address(mockBridge), l1Token, NAME, SYMBOL, DECIMALS, emptyAllowlist2
        );
    }

    // ============ Role Separation Tests ============

    function testRoleSeparationCriticalRoles() public {
        address defaultAdmin = makeAddr("defaultAdmin");
        address upgrader = makeAddr("upgrader");
        address pauser = makeAddr("pauser");
        address allowlistAdmin = makeAddr("allowlistAdmin");

        CNSTokenL2 separatedToken =
            _deployInitializedProxy(defaultAdmin, upgrader, pauser, allowlistAdmin, bridge, l1Token);

        // Critical roles should be assigned correctly
        assertTrue(separatedToken.hasRole(DEFAULT_ADMIN_ROLE, defaultAdmin));
        assertTrue(separatedToken.hasRole(UPGRADER_ROLE, upgrader));
    }

    function testRoleSeparationOperationalRolesAssigned() public {
        address defaultAdmin = makeAddr("defaultAdmin");
        address upgrader = makeAddr("upgrader");
        address pauser = makeAddr("pauser");
        address allowlistAdmin = makeAddr("allowlistAdmin");

        CNSTokenL2 separatedToken =
            _deployInitializedProxy(defaultAdmin, upgrader, pauser, allowlistAdmin, bridge, l1Token);

        // Operational roles should be assigned to dedicated addresses
        assertTrue(separatedToken.hasRole(PAUSER_ROLE, pauser));
        assertTrue(separatedToken.hasRole(ALLOWLIST_ADMIN_ROLE, allowlistAdmin));

        // DefaultAdmin should also have operational roles as backup
        assertTrue(separatedToken.hasRole(PAUSER_ROLE, defaultAdmin));
        assertTrue(separatedToken.hasRole(ALLOWLIST_ADMIN_ROLE, defaultAdmin));
    }

    function testRoleSeparationPauserCanPause() public {
        address defaultAdmin = makeAddr("defaultAdmin");
        address upgrader = makeAddr("upgrader");
        address pauser = makeAddr("pauser");
        address allowlistAdmin = makeAddr("allowlistAdmin");

        CNSTokenL2 separatedToken =
            _deployInitializedProxy(defaultAdmin, upgrader, pauser, allowlistAdmin, bridge, l1Token);

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
        address defaultAdmin = makeAddr("defaultAdmin");
        address upgrader = makeAddr("upgrader");
        address pauser = makeAddr("pauser");
        address allowlistAdmin = makeAddr("allowlistAdmin");
        address testUser = makeAddr("testUser");

        CNSTokenL2 separatedToken =
            _deployInitializedProxy(defaultAdmin, upgrader, pauser, allowlistAdmin, bridge, l1Token);

        // Allowlist admin should be able to manage allowlist
        vm.prank(allowlistAdmin);
        separatedToken.setSenderAllowed(testUser, true);
        assertTrue(separatedToken.isSenderAllowlisted(testUser));

        vm.prank(allowlistAdmin);
        separatedToken.setSenderAllowed(testUser, false);
        assertFalse(separatedToken.isSenderAllowlisted(testUser));
    }

    function testRoleSeparationOnlyUpgraderCanUpgrade() public {
        address defaultAdmin = makeAddr("defaultAdmin");
        address upgrader = makeAddr("upgrader");
        address pauser = makeAddr("pauser");
        address allowlistAdmin = makeAddr("allowlistAdmin");

        CNSTokenL2 separatedToken =
            _deployInitializedProxy(defaultAdmin, upgrader, pauser, allowlistAdmin, bridge, l1Token);
        CNSTokenL2MockV2 newImpl = new CNSTokenL2MockV2();

        // Upgrader can upgrade
        vm.prank(upgrader);
        separatedToken.upgradeToAndCall(address(newImpl), "");

        // Pauser cannot upgrade
        CNSTokenL2 separatedToken2 =
            _deployInitializedProxy(defaultAdmin, upgrader, pauser, allowlistAdmin, bridge, l1Token);
        vm.prank(pauser);
        vm.expectRevert();
        separatedToken2.upgradeToAndCall(address(newImpl), "");

        // Allowlist admin cannot upgrade
        CNSTokenL2 separatedToken3 =
            _deployInitializedProxy(defaultAdmin, upgrader, pauser, allowlistAdmin, bridge, l1Token);
        vm.prank(allowlistAdmin);
        vm.expectRevert();
        separatedToken3.upgradeToAndCall(address(newImpl), "");
    }

    function testRoleSeparationDefaultAdminAsBackupCanPause() public {
        address defaultAdmin = makeAddr("defaultAdmin");
        address upgrader = makeAddr("upgrader");
        address pauser = makeAddr("pauser");
        address allowlistAdmin = makeAddr("allowlistAdmin");

        CNSTokenL2 separatedToken =
            _deployInitializedProxy(defaultAdmin, upgrader, pauser, allowlistAdmin, bridge, l1Token);

        // DefaultAdmin as backup can pause
        vm.prank(defaultAdmin);
        separatedToken.pause();
        assertTrue(separatedToken.paused());
    }

    function testRoleSeparationDefaultAdminAsBackupCanManageAllowlist() public {
        address defaultAdmin = makeAddr("defaultAdmin");
        address upgrader = makeAddr("upgrader");
        address pauser = makeAddr("pauser");
        address allowlistAdmin = makeAddr("allowlistAdmin");
        address testUser = makeAddr("testUser");

        CNSTokenL2 separatedToken =
            _deployInitializedProxy(defaultAdmin, upgrader, pauser, allowlistAdmin, bridge, l1Token);

        // DefaultAdmin as backup can manage allowlist
        vm.prank(defaultAdmin);
        separatedToken.setSenderAllowed(testUser, true);
        assertTrue(separatedToken.isSenderAllowlisted(testUser));
    }
}

contract CNSTokenL2MockV2 is CNSTokenL2 {
    function version() public pure override returns (string memory) {
        return "2.0.0";
    }
}

// Mock bridge contract for testing
contract MockBridge {
    // Empty contract that just needs to exist

    }

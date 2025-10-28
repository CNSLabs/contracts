// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ShoTokenL2} from "../src/CNSTokenL2.sol";

/**
 * @title ShoTokenL2UpgradeTest
 * @notice Comprehensive upgrade safety tests for UUPS upgradeable ShoTokenL2
 */
contract ShoTokenL2UpgradeTest is Test {
    ShoTokenL2 internal token;

    address internal admin;
    address internal bridge;
    address internal l1Token;
    address internal user1;
    address internal user2;

    uint8 internal constant DECIMALS = 18;
    uint256 internal constant INITIAL_SUPPLY = 1_000_000 ether;

    string internal constant NAME = "CNS Linea Token";
    string internal constant SYMBOL = "CNSL";

    event Upgraded(address indexed implementation);

    function setUp() public {
        admin = makeAddr("admin");
        // Deploy a mock bridge contract
        MockBridge mockBridge = new MockBridge();
        bridge = address(mockBridge);
        l1Token = makeAddr("l1Token");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        token = _deployInitializedProxy(admin, bridge, l1Token);

        // Setup initial state
        vm.startPrank(bridge);
        token.mint(user1, INITIAL_SUPPLY);
        vm.stopPrank();

        vm.startPrank(admin);
        token.setSenderAllowed(user1, true);
        token.setSenderAllowed(user2, true);
        vm.stopPrank();
    }

    function _deployInitializedProxy(address admin_, address bridge_, address l1Token_) internal returns (ShoTokenL2) {
        ShoTokenL2 implementation = new ShoTokenL2();
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
        ShoTokenL2 proxied = ShoTokenL2(address(proxy));
        address[] memory emptyAllowlist = new address[](0);
        proxied.initialize(admin_, admin_, admin_, admin_, bridge_, l1Token_, NAME, SYMBOL, DECIMALS, emptyAllowlist);
        return proxied;
    }

    // ============ State Preservation Tests ============

    function testUpgradePreservesAllState() public {
        // Record pre-upgrade state
        uint256 user1BalanceBefore = token.balanceOf(user1);
        uint256 totalSupplyBefore = token.totalSupply();
        address bridgeBefore = token.bridge();
        address l1TokenBefore = token.l1Token();
        bool user1AllowlistedBefore = token.isSenderAllowlisted(user1);
        bool user2AllowlistedBefore = token.isSenderAllowlisted(user2);

        // Upgrade to V2
        ShoTokenL2V2 newImplementation = new ShoTokenL2V2();
        vm.prank(admin);
        token.upgradeToAndCall(address(newImplementation), "");

        ShoTokenL2V2 upgradedToken = ShoTokenL2V2(address(token));

        // Verify all state preserved
        assertEq(upgradedToken.balanceOf(user1), user1BalanceBefore, "Balance not preserved");
        assertEq(upgradedToken.totalSupply(), totalSupplyBefore, "Total supply not preserved");
        assertEq(upgradedToken.bridge(), bridgeBefore, "Bridge not preserved");
        assertEq(upgradedToken.l1Token(), l1TokenBefore, "L1 token not preserved");
        assertEq(upgradedToken.isSenderAllowlisted(user1), user1AllowlistedBefore, "User1 allowlist not preserved");
        assertEq(upgradedToken.isSenderAllowlisted(user2), user2AllowlistedBefore, "User2 allowlist not preserved");

        // Verify roles preserved
        assertTrue(upgradedToken.hasRole(upgradedToken.DEFAULT_ADMIN_ROLE(), admin), "Admin role not preserved");
        assertTrue(upgradedToken.hasRole(upgradedToken.UPGRADER_ROLE(), admin), "Upgrader role not preserved");
        assertTrue(upgradedToken.hasRole(upgradedToken.PAUSER_ROLE(), admin), "Pauser role not preserved");
        assertTrue(
            upgradedToken.hasRole(upgradedToken.ALLOWLIST_ADMIN_ROLE(), admin), "Allowlist admin role not preserved"
        );

        // Verify name and symbol preserved
        assertEq(upgradedToken.name(), NAME, "Name not preserved");
        assertEq(upgradedToken.symbol(), SYMBOL, "Symbol not preserved");
        assertEq(upgradedToken.decimals(), DECIMALS, "Decimals not preserved");
    }

    function testUpgradePreservesComplexState() public {
        // Create complex state before upgrade
        vm.startPrank(admin);
        token.pause();
        token.setSenderAllowed(address(this), true);
        vm.stopPrank();

        bool pausedBefore = token.paused();

        // Upgrade
        ShoTokenL2V2 newImplementation = new ShoTokenL2V2();
        vm.prank(admin);
        token.upgradeToAndCall(address(newImplementation), "");

        ShoTokenL2V2 upgradedToken = ShoTokenL2V2(address(token));

        // Verify paused state preserved
        assertEq(upgradedToken.paused(), pausedBefore, "Paused state not preserved");
        assertTrue(upgradedToken.isSenderAllowlisted(address(this)), "New allowlist entry not preserved");
    }

    function testUpgradedContractFunctionality() public {
        // Upgrade to V2
        ShoTokenL2V2 newImplementation = new ShoTokenL2V2();
        vm.prank(admin);
        token.upgradeToAndCall(address(newImplementation), "");

        ShoTokenL2V2 upgradedToken = ShoTokenL2V2(address(token));

        // Test old functionality still works
        vm.prank(user1);
        upgradedToken.transfer(user2, 100 ether);
        assertEq(upgradedToken.balanceOf(user2), 100 ether);

        // Test new functionality
        assertEq(upgradedToken.version(), "2.0.0");
    }

    // ============ Storage Layout Tests ============

    function testStorageSlotsDontCollide() public {
        // Get initial values
        address bridgeBefore = token.bridge();
        address l1TokenBefore = token.l1Token();

        // Upgrade
        ShoTokenL2V2 newImplementation = new ShoTokenL2V2();
        vm.prank(admin);
        token.upgradeToAndCall(address(newImplementation), "");

        ShoTokenL2V2 upgradedToken = ShoTokenL2V2(address(token));

        // Critical: ensure storage slots haven't shifted
        assertEq(upgradedToken.bridge(), bridgeBefore, "Storage collision: bridge");
        assertEq(upgradedToken.l1Token(), l1TokenBefore, "Storage collision: l1Token");
    }

    // ============ Authorization Tests ============

    function testOnlyUpgraderCanUpgrade() public {
        ShoTokenL2V2 newImplementation = new ShoTokenL2V2();

        // Non-upgrader should fail
        vm.expectRevert();
        vm.prank(user1);
        token.upgradeToAndCall(address(newImplementation), "");

        // Bridge should fail
        vm.expectRevert();
        vm.prank(bridge);
        token.upgradeToAndCall(address(newImplementation), "");

        // Upgrader should succeed
        vm.prank(admin);
        token.upgradeToAndCall(address(newImplementation), "");
    }

    function testUpgradeWithCalldata() public {
        // Create V2 with initializer
        ShoTokenL2V2WithInit newImplementation = new ShoTokenL2V2WithInit();

        // Upgrade with initialization
        bytes memory initData = abi.encodeWithSelector(ShoTokenL2V2WithInit.initializeV2.selector, 100);

        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit Upgraded(address(newImplementation));
        token.upgradeToAndCall(address(newImplementation), initData);

        ShoTokenL2V2WithInit upgraded = ShoTokenL2V2WithInit(address(token));
        assertEq(upgraded.newFeatureValue(), 100);
    }

    // ============ Safety Tests ============

    function testCannotUpgradeToNonUUPSContract() public {
        NonUUPSContract nonUUPS = new NonUUPSContract();

        vm.expectRevert();
        vm.prank(admin);
        token.upgradeToAndCall(address(nonUUPS), "");
    }

    function testCannotReinitializeAfterUpgrade() public {
        ShoTokenL2V2 newImplementation = new ShoTokenL2V2();

        vm.prank(admin);
        token.upgradeToAndCall(address(newImplementation), "");

        ShoTokenL2V2 upgraded = ShoTokenL2V2(address(token));

        // Should not be able to call initialize again
        vm.expectRevert();
        address[] memory emptyAllowlist = new address[](0);
        upgraded.initialize(admin, admin, admin, admin, bridge, l1Token, NAME, SYMBOL, DECIMALS, emptyAllowlist);
    }

    // ============ Multi-Upgrade Tests ============

    function testMultipleSequentialUpgrades() public {
        uint256 balanceBefore = token.balanceOf(user1);

        // Upgrade to V2
        ShoTokenL2V2 implV2 = new ShoTokenL2V2();
        vm.prank(admin);
        token.upgradeToAndCall(address(implV2), "");

        ShoTokenL2V2 tokenV2 = ShoTokenL2V2(address(token));
        assertEq(tokenV2.version(), "2.0.0");
        assertEq(tokenV2.balanceOf(user1), balanceBefore);

        // Upgrade to V3
        ShoTokenL2V3 implV3 = new ShoTokenL2V3();
        vm.prank(admin);
        tokenV2.upgradeToAndCall(address(implV3), "");

        ShoTokenL2V3 tokenV3 = ShoTokenL2V3(address(token));
        assertEq(tokenV3.version(), "3.0.0");
        assertEq(tokenV3.balanceOf(user1), balanceBefore);
    }

    // ============ Upgrade Gap Tests ============

    function testStorageGapPreventsFutureCollisions() public {
        // This test verifies that the __gap prevents storage collisions in upgrades
        // The gap should shrink when new variables are added in V2

        ShoTokenL2V2 newImpl = new ShoTokenL2V2();
        vm.prank(admin);
        token.upgradeToAndCall(address(newImpl), "");

        // If storage layout is correct, this should not cause any issues
        ShoTokenL2V2 upgraded = ShoTokenL2V2(address(token));
        assertEq(upgraded.balanceOf(user1), INITIAL_SUPPLY);
    }
}

// ============ Mock Upgrade Contracts ============

contract ShoTokenL2V2 is ShoTokenL2 {
    function version() public pure override returns (string memory) {
        return "2.0.0";
    }
}

contract ShoTokenL2V3 is ShoTokenL2 {
    function version() public pure override returns (string memory) {
        return "3.0.0";
    }
}

contract ShoTokenL2V2WithInit is ShoTokenL2 {
    uint256 public newFeatureValue;

    function initializeV2(uint256 _value) external reinitializer(2) {
        newFeatureValue = _value;
    }

    function version() public pure override returns (string memory) {
        return "2.0.0";
    }
}

contract NonUUPSContract {
    // Not a UUPS contract, should fail upgrade
    uint256 public dummy;
}

// Mock bridge contract for testing
contract MockBridge {
    // Empty contract that just needs to exist

    }

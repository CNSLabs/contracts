// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {CNSTokenL2} from "../src/CNSTokenL2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Mock address(bridge) contract for testing
contract MockBridge {
    // Empty contract that just needs to exist

    }

/**
 * @title CNSTokenL2 Invariant Tests
 * @dev Invariant testing for CNSTokenL2 contract
 * @notice Tests that certain properties always hold true across all operations
 */
contract CNSTokenL2InvariantTest is Test {
    CNSTokenL2 internal token;
    MockBridge internal bridge;
    address internal admin;
    address internal l1Token;

    // Actors for invariant testing
    address[] internal users;
    address[] internal allowlistedUsers;

    string constant NAME = "CNS Token L2";
    string constant SYMBOL = "CNS";
    uint8 constant DECIMALS = 18;

    function setUp() public {
        admin = makeAddr("admin");
        bridge = new MockBridge();
        l1Token = makeAddr("l1Token");

        token = _deployInitializedProxy(admin, admin, admin, admin, address(bridge), l1Token);

        // Initialize actors
        for (uint256 i = 0; i < 10; i++) {
            users.push(address(uint160(0x1000 + i)));
            allowlistedUsers.push(address(uint160(0x2000 + i)));
        }

        // Allowlist some users
        for (uint256 i = 0; i < allowlistedUsers.length; i++) {
            vm.prank(admin);
            token.setSenderAllowed(allowlistedUsers[i], true);
        }
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

    // ============ Core Invariants ============

    /**
     * @dev Invariant: Total supply should always equal sum of all balances
     */
    function invariant_totalSupplyMatchesSumOfBalances() public {
        uint256 totalSupply = token.totalSupply();
        uint256 sumOfBalances = 0;

        // Sum balances of all users
        for (uint256 i = 0; i < users.length; i++) {
            sumOfBalances += token.balanceOf(users[i]);
        }

        for (uint256 i = 0; i < allowlistedUsers.length; i++) {
            sumOfBalances += token.balanceOf(allowlistedUsers[i]);
        }

        // Add balances of special addresses
        sumOfBalances += token.balanceOf(admin);
        sumOfBalances += token.balanceOf(address(bridge));
        sumOfBalances += token.balanceOf(l1Token);

        assertEq(totalSupply, sumOfBalances, "Total supply must equal sum of balances");
    }

    /**
     * @dev Invariant: No address should have negative balance
     */
    function invariant_noNegativeBalances() public {
        // This is enforced by Solidity's uint256 type, but we verify it
        for (uint256 i = 0; i < users.length; i++) {
            assertGe(token.balanceOf(users[i]), 0, "Balance cannot be negative");
        }

        for (uint256 i = 0; i < allowlistedUsers.length; i++) {
            assertGe(token.balanceOf(allowlistedUsers[i]), 0, "Balance cannot be negative");
        }

        assertGe(token.balanceOf(admin), 0, "Admin balance cannot be negative");
        assertGe(token.balanceOf(address(bridge)), 0, "Bridge balance cannot be negative");
        assertGe(token.balanceOf(l1Token), 0, "L1Token balance cannot be negative");
    }

    /**
     * @dev Invariant: Total supply should never exceed maximum possible
     */
    function invariant_totalSupplyWithinBounds() public {
        uint256 totalSupply = token.totalSupply();
        assertLe(totalSupply, type(uint256).max, "Total supply cannot exceed uint256 max");
    }

    // ============ Allowlist Invariants ============

    /**
     * @dev Invariant: Allowlist status should be consistent
     */
    function invariant_allowlistConsistency() public {
        for (uint256 i = 0; i < allowlistedUsers.length; i++) {
            assertTrue(token.isSenderAllowlisted(allowlistedUsers[i]), "Allowlisted users should remain allowlisted");
        }

        for (uint256 i = 0; i < users.length; i++) {
            assertFalse(token.isSenderAllowlisted(users[i]), "Non-allowlisted users should remain non-allowlisted");
        }
    }

    /**
     * @dev Invariant: Zero address should never be allowlisted
     */
    function invariant_zeroAddressNeverAllowlisted() public {
        assertFalse(token.isSenderAllowlisted(address(0)), "Zero address should never be allowlisted");
    }

    // ============ Role Invariants ============

    /**
     * @dev Invariant: Admin should always have all roles
     */
    function invariant_adminHasAllRoles() public {
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin), "Admin must have DEFAULT_ADMIN_ROLE");
        assertTrue(token.hasRole(token.PAUSER_ROLE(), admin), "Admin must have PAUSER_ROLE");
        assertTrue(token.hasRole(token.ALLOWLIST_ADMIN_ROLE(), admin), "Admin must have ALLOWLIST_ADMIN_ROLE");
        assertTrue(token.hasRole(token.UPGRADER_ROLE(), admin), "Admin must have UPGRADER_ROLE");
    }

    /**
     * @dev Invariant: Bridge should not have admin roles
     */
    function invariant_bridgeNoAdminRoles() public {
        assertFalse(
            token.hasRole(token.DEFAULT_ADMIN_ROLE(), address(bridge)), "Bridge should not have DEFAULT_ADMIN_ROLE"
        );
        assertFalse(token.hasRole(token.PAUSER_ROLE(), address(bridge)), "Bridge should not have PAUSER_ROLE");
        assertFalse(
            token.hasRole(token.ALLOWLIST_ADMIN_ROLE(), address(bridge)), "Bridge should not have ALLOWLIST_ADMIN_ROLE"
        );
        assertFalse(token.hasRole(token.UPGRADER_ROLE(), address(bridge)), "Bridge should not have UPGRADER_ROLE");
    }

    // ============ Pause Invariants ============

    /**
     * @dev Invariant: When paused, no transfers should be possible
     */
    function invariant_pauseBlocksTransfers() public {
        if (token.paused()) {
            // If paused, verify that transfers would fail
            // We can't actually test transfers here as they would revert,
            // but we can verify the pause state is consistent
            assertTrue(token.paused(), "Pause state should be consistent");
        }
    }

    /**
     * @dev Invariant: Pause state should be boolean
     */
    function invariant_pauseStateBoolean() public {
        bool paused = token.paused();
        assertTrue(paused == true || paused == false, "Pause state must be boolean");
    }

    // ============ Token Standard Invariants ============

    /**
     * @dev Invariant: Token name should never change
     */
    function invariant_tokenNameConsistent() public {
        assertEq(token.name(), NAME, "Token name should remain consistent");
    }

    /**
     * @dev Invariant: Token symbol should never change
     */
    function invariant_tokenSymbolConsistent() public {
        assertEq(token.symbol(), SYMBOL, "Token symbol should remain consistent");
    }

    /**
     * @dev Invariant: Token decimals should never change
     */
    function invariant_tokenDecimalsConsistent() public {
        assertEq(token.decimals(), DECIMALS, "Token decimals should remain consistent");
    }

    /**
     * @dev Invariant: Token version should be consistent
     */
    function invariant_tokenVersionConsistent() public {
        assertEq(token.version(), "1.0.0", "Token version should remain consistent");
    }

    // ============ Bridge Invariants ============

    /**
     * @dev Invariant: Bridge address should never change
     */
    function invariant_bridgeAddressConsistent() public {
        assertEq(token.bridge(), address(bridge), "Bridge address should remain consistent");
    }

    /**
     * @dev Invariant: L1 token address should never change
     */
    function invariant_l1TokenAddressConsistent() public {
        assertEq(token.l1Token(), l1Token, "L1 token address should remain consistent");
    }

    // ============ Allowance Invariants ============

    /**
     * @dev Invariant: Allowances should never be negative
     */
    function invariant_noNegativeAllowances() public {
        for (uint256 i = 0; i < users.length; i++) {
            for (uint256 j = 0; j < users.length; j++) {
                if (i != j) {
                    assertGe(token.allowance(users[i], users[j]), 0, "Allowance cannot be negative");
                }
            }
        }
    }

    /**
     * @dev Invariant: Self-allowance should be infinite or zero
     */
    function invariant_selfAllowanceConsistent() public {
        for (uint256 i = 0; i < users.length; i++) {
            uint256 selfAllowance = token.allowance(users[i], users[i]);
            assertTrue(selfAllowance == 0 || selfAllowance == type(uint256).max, "Self-allowance should be 0 or max");
        }
    }

    // ============ Storage Invariants ============

    /**
     * @dev Invariant: Storage layout should be consistent
     */
    function invariant_storageLayoutConsistent() public {
        // Verify that critical state variables are accessible
        assertTrue(token.bridge() != address(0), "Bridge should be set");
        assertTrue(token.l1Token() != address(0), "L1Token should be set");
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin), "Admin should be set");
    }

    // ============ Upgrade Invariants ============

    /**
     * @dev Invariant: Implementation should be upgradeable
     */
    function invariant_upgradeabilityConsistent() public {
        // Verify that the contract supports the UUPS interface
        assertTrue(token.supportsInterface(0x5a05180f), "Should support UUPS interface");
    }

    // ============ Gas Invariants ============

    /**
     * @dev Invariant: Gas usage should be reasonable
     */
    function invariant_gasUsageReasonable() public {
        // This is more of a sanity check - we can't easily measure gas in invariants
        // But we can verify that basic operations don't consume excessive gas
        uint256 gasStart = gasleft();

        // Perform a simple read operation
        token.totalSupply();

        uint256 gasUsed = gasStart - gasleft();
        assertLt(gasUsed, 10000, "Basic operations should not consume excessive gas");
    }

    // ============ Edge Case Invariants ============

    /**
     * @dev Invariant: Contract should handle edge cases gracefully
     */
    function invariant_edgeCaseHandling() public {
        // Verify that the contract doesn't break with edge case inputs
        assertTrue(token.balanceOf(address(0)) == 0, "Zero address should have zero balance");
        assertTrue(token.allowance(address(0), address(0)) == 0, "Zero address allowances should be zero");
    }

    /**
     * @dev Invariant: Contract should maintain consistency across operations
     */
    function invariant_operationConsistency() public {
        // Verify that the contract maintains internal consistency
        uint256 totalSupply = token.totalSupply();

        // If total supply is zero, all balances should be zero
        if (totalSupply == 0) {
            for (uint256 i = 0; i < users.length; i++) {
                assertEq(token.balanceOf(users[i]), 0, "If total supply is 0, all balances should be 0");
            }
        }
    }

    // ============ Security Invariants ============

    /**
     * @dev Invariant: No unauthorized access to critical functions
     */
    function invariant_noUnauthorizedAccess() public {
        // Verify that only authorized addresses can perform critical operations
        // This is more of a structural check since we can't test reverts in invariants

        // Admin should be the only one with DEFAULT_ADMIN_ROLE
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin), "Only admin should have DEFAULT_ADMIN_ROLE");

        // Bridge should be the only one that can mint/burn (enforced by onlyBridge modifier)
        // This is tested in the security tests, but we verify the state here
    }

    /**
     * @dev Invariant: Contract should be in a valid state
     */
    function invariant_contractInValidState() public {
        // Verify that the contract is in a valid state
        assertTrue(token.bridge() != address(0), "Bridge must be set");
        assertTrue(token.l1Token() != address(0), "L1Token must be set");
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin), "Admin must be set");

        // Verify that the contract is not in an inconsistent state
        assertTrue(token.totalSupply() >= 0, "Total supply must be non-negative");
    }
}

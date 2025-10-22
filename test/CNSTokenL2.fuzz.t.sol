// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {CNSTokenL2} from "../src/CNSTokenL2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Mock bridge contract for testing
contract MockBridge {
    // Empty contract that just needs to exist

    }

/**
 * @title CNSTokenL2 Fuzz Tests
 * @dev Property-based testing for CNSTokenL2 contract
 * @notice Tests contract behavior with random inputs to discover edge cases
 */
contract CNSTokenL2FuzzTest is Test {
    CNSTokenL2 internal token;
    MockBridge internal bridge;
    address internal admin;
    address internal l1Token;

    string constant NAME = "CNS Token L2";
    string constant SYMBOL = "CNS";
    uint8 constant DECIMALS = 18;

    function setUp() public {
        admin = makeAddr("admin");
        bridge = new MockBridge();
        l1Token = makeAddr("l1Token");

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

    // ============ Allowlist Management Fuzz Tests ============

    function testFuzzAllowlistManagement(address account, bool allowed) public {
        vm.assume(account != address(0));
        vm.assume(account != admin);

        vm.prank(admin);
        token.setSenderAllowed(account, allowed);

        assertEq(token.isSenderAllowlisted(account), allowed);
    }

    function testFuzzAllowlistToggle(address account) public {
        vm.assume(account != address(0));
        vm.assume(account != admin);

        // Set to true
        vm.prank(admin);
        token.setSenderAllowed(account, true);
        assertTrue(token.isSenderAllowlisted(account));

        // Set to false
        vm.prank(admin);
        token.setSenderAllowed(account, false);
        assertFalse(token.isSenderAllowlisted(account));

        // Set to true again
        vm.prank(admin);
        token.setSenderAllowed(account, true);
        assertTrue(token.isSenderAllowlisted(account));
    }

    function testFuzzBatchAllowlistManagement(address[] calldata accounts, bool allowed) public {
        vm.assume(accounts.length > 0);
        vm.assume(accounts.length <= 200); // Within batch limit

        // Ensure no zero addresses
        for (uint256 i = 0; i < accounts.length; i++) {
            vm.assume(accounts[i] != address(0));
            vm.assume(accounts[i] != admin);
        }

        vm.prank(admin);
        token.setSenderAllowedBatch(accounts, allowed);

        // Verify all accounts have correct allowlist status
        for (uint256 i = 0; i < accounts.length; i++) {
            assertEq(token.isSenderAllowlisted(accounts[i]), allowed);
        }
    }

    // ============ Transfer Fuzz Tests ============

    function testFuzzTransferWithAllowlist(address from, address to, uint256 amount) public {
        vm.assume(from != address(0));
        vm.assume(to != address(0));
        vm.assume(from != to);
        vm.assume(amount > 0);
        vm.assume(amount <= 1000000 ether); // Reasonable upper bound

        // Mint tokens to from
        vm.prank(address(bridge));
        token.mint(from, amount);

        // Allowlist from
        vm.prank(admin);
        token.setSenderAllowed(from, true);

        // Transfer should work
        vm.prank(from);
        token.transfer(to, amount);

        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(from), 0);
    }

    function testFuzzTransferFromWithAllowlist(address from, address to, uint256 amount) public {
        vm.assume(from != address(0));
        vm.assume(to != address(0));
        vm.assume(from != to);
        vm.assume(amount > 0);
        vm.assume(amount <= 1000000 ether);

        address spender = makeAddr("spender");

        // Mint tokens to from
        vm.prank(address(bridge));
        token.mint(from, amount);

        // Allowlist from
        vm.prank(admin);
        token.setSenderAllowed(from, true);

        // Approve spender
        vm.prank(from);
        token.approve(spender, amount);

        // TransferFrom should work
        vm.prank(spender);
        token.transferFrom(from, to, amount);

        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(from), 0);
    }

    function testFuzzTransferFailsWithoutAllowlist(address from, address to, uint256 amount) public {
        vm.assume(from != address(0));
        vm.assume(to != address(0));
        vm.assume(from != to);
        vm.assume(from != admin); // Ensure from is not admin (who is allowlisted)
        vm.assume(from != address(bridge)); // Ensure from is not bridge (who is allowlisted)
        vm.assume(from != address(token)); // Ensure from is not the proxy contract (who is allowlisted)
        vm.assume(amount > 0);
        vm.assume(amount <= 1000000 ether);

        // Mint tokens to from
        vm.prank(address(bridge));
        token.mint(from, amount);

        // Don't allowlist from

        // Transfer should fail
        vm.prank(from);
        vm.expectRevert(CNSTokenL2.SenderNotAllowlisted.selector);
        token.transfer(to, amount);
    }

    // ============ Mint/Burn Fuzz Tests ============

    function testFuzzMintToAnyAddress(address to, uint256 amount) public {
        vm.assume(to != address(0));
        vm.assume(amount > 0);
        vm.assume(amount <= 1000000 ether);

        uint256 initialSupply = token.totalSupply();

        vm.prank(address(bridge));
        token.mint(to, amount);

        assertEq(token.balanceOf(to), amount);
        assertEq(token.totalSupply(), initialSupply + amount);
    }

    function testFuzzBurnFromAnyAddress(address from, uint256 amount) public {
        vm.assume(from != address(0));
        vm.assume(amount > 0);
        vm.assume(amount <= 1000000 ether);

        // Mint tokens first
        vm.prank(address(bridge));
        token.mint(from, amount);

        uint256 initialSupply = token.totalSupply();

        // Approve bridge to burn
        vm.prank(from);
        token.approve(address(bridge), amount);

        // Burn tokens
        vm.prank(address(bridge));
        token.burn(from, amount);

        assertEq(token.balanceOf(from), 0);
        assertEq(token.totalSupply(), initialSupply - amount);
    }

    function testFuzzBurnFailsWithoutApproval(address from, uint256 amount) public {
        vm.assume(from != address(0));
        vm.assume(amount > 0);
        vm.assume(amount <= 1000000 ether);

        // Mint tokens first
        vm.prank(address(bridge));
        token.mint(from, amount);

        // Don't approve bridge

        // Burn should fail
        vm.prank(address(bridge));
        vm.expectRevert();
        token.burn(from, amount);
    }

    // ============ Pause Fuzz Tests ============

    function testFuzzPauseBlocksAllTransfers(address from, address to, uint256 amount) public {
        vm.assume(from != address(0));
        vm.assume(to != address(0));
        vm.assume(from != to);
        vm.assume(amount > 0);
        vm.assume(amount <= 1000000 ether);

        // Mint tokens and allowlist
        vm.prank(address(bridge));
        token.mint(from, amount);

        vm.prank(admin);
        token.setSenderAllowed(from, true);

        // Pause contract
        vm.prank(admin);
        token.pause();

        // All transfers should fail
        vm.prank(from);
        vm.expectRevert();
        token.transfer(to, amount);
    }

    function testFuzzUnpauseRestoresTransfers(address from, address to, uint256 amount) public {
        vm.assume(from != address(0));
        vm.assume(to != address(0));
        vm.assume(from != to);
        vm.assume(amount > 0);
        vm.assume(amount <= 1000000 ether);

        // Mint tokens and allowlist
        vm.prank(address(bridge));
        token.mint(from, amount);

        vm.prank(admin);
        token.setSenderAllowed(from, true);

        // Pause and unpause
        vm.prank(admin);
        token.pause();

        vm.prank(admin);
        token.unpause();

        // Transfer should work again
        vm.prank(from);
        token.transfer(to, amount);

        assertEq(token.balanceOf(to), amount);
    }

    // ============ Role Management Fuzz Tests ============

    function testFuzzRoleGranting(address account, bytes32 role) public {
        vm.assume(account != address(0));
        vm.assume(account != admin);

        vm.prank(admin);
        token.grantRole(role, account);

        assertTrue(token.hasRole(role, account));
    }

    function testFuzzRoleRevoking(address account, bytes32 role) public {
        vm.assume(account != address(0));
        vm.assume(account != admin);

        // First grant role
        vm.prank(admin);
        token.grantRole(role, account);

        // Then revoke it
        vm.prank(admin);
        token.revokeRole(role, account);

        assertFalse(token.hasRole(role, account));
    }

    // ============ Edge Case Fuzz Tests ============

    function testFuzzZeroAmountTransfers(address from, address to) public {
        vm.assume(from != address(0));
        vm.assume(to != address(0));
        vm.assume(from != to);

        // Mint some tokens
        vm.prank(address(bridge));
        token.mint(from, 1000 ether);

        // Allowlist from
        vm.prank(admin);
        token.setSenderAllowed(from, true);

        // Zero amount transfer should work
        vm.prank(from);
        token.transfer(to, 0);

        assertEq(token.balanceOf(from), 1000 ether);
        assertEq(token.balanceOf(to), 0);
    }

    function testFuzzSelfTransfer(address account, uint256 amount) public {
        vm.assume(account != address(0));
        vm.assume(amount > 0);
        vm.assume(amount <= 1000000 ether);

        // Mint tokens
        vm.prank(address(bridge));
        token.mint(account, amount);

        // Allowlist account
        vm.prank(admin);
        token.setSenderAllowed(account, true);

        // Self transfer should work
        vm.prank(account);
        token.transfer(account, amount);

        // Balance should remain the same
        assertEq(token.balanceOf(account), amount);
    }

    function testFuzzAllowlistToggleAffectsTransfers(address from, address to, uint256 amount) public {
        vm.assume(from != address(0));
        vm.assume(to != address(0));
        vm.assume(from != to);
        vm.assume(from != admin); // Ensure from is not admin (who is allowlisted)
        vm.assume(from != address(bridge)); // Ensure from is not bridge (who is allowlisted)
        vm.assume(from != address(token)); // Ensure from is not the proxy contract (who is allowlisted)
        vm.assume(amount > 0);
        vm.assume(amount <= 1000000 ether);

        // Mint tokens
        vm.prank(address(bridge));
        token.mint(from, amount);

        // Initially not allowlisted - transfer should fail
        vm.prank(from);
        vm.expectRevert(CNSTokenL2.SenderNotAllowlisted.selector);
        token.transfer(to, amount);

        // Allowlist from
        vm.prank(admin);
        token.setSenderAllowed(from, true);

        // Transfer should work now
        vm.prank(from);
        token.transfer(to, amount);

        assertEq(token.balanceOf(to), amount);

        // Remove from allowlist
        vm.prank(admin);
        token.setSenderAllowed(from, false);

        // Mint more tokens
        vm.prank(address(bridge));
        token.mint(from, amount);

        // Transfer should fail again
        vm.prank(from);
        vm.expectRevert(CNSTokenL2.SenderNotAllowlisted.selector);
        token.transfer(to, amount);
    }

    // ============ Gas Limit Fuzz Tests ============

    function testFuzzBatchSizeLimits(uint256 batchSize) public {
        vm.assume(batchSize > 200 && batchSize < 1000); // Exceed limit but keep reasonable for gas

        address[] memory accounts = new address[](batchSize);
        for (uint256 i = 0; i < batchSize; i++) {
            accounts[i] = address(uint160(i + 1));
        }

        vm.prank(admin);
        vm.expectRevert(CNSTokenL2.BatchTooLarge.selector);
        token.setSenderAllowedBatch(accounts, true);
    }

    function testFuzzEmptyBatch() public {
        address[] memory accounts = new address[](0);

        vm.prank(admin);
        vm.expectRevert(CNSTokenL2.EmptyBatch.selector);
        token.setSenderAllowedBatch(accounts, true);
    }

    // ============ State Consistency Fuzz Tests ============

    function testFuzzTotalSupplyConsistency(uint256[] calldata amounts) public {
        vm.assume(amounts.length > 0);
        vm.assume(amounts.length <= 100); // Reasonable limit

        uint256 expectedTotalSupply = 0;

        for (uint256 i = 0; i < amounts.length; i++) {
            vm.assume(amounts[i] > 0);
            vm.assume(amounts[i] <= 1000000 ether);

            address recipient = address(uint160(i + 1));

            vm.prank(address(bridge));
            token.mint(recipient, amounts[i]);

            expectedTotalSupply += amounts[i];
        }

        assertEq(token.totalSupply(), expectedTotalSupply);
    }

    function testFuzzBalanceConsistency(address account, uint256 amount) public {
        vm.assume(account != address(0));
        vm.assume(amount > 0);
        vm.assume(amount <= 1000000 ether);

        uint256 initialBalance = token.balanceOf(account);

        vm.prank(address(bridge));
        token.mint(account, amount);

        assertEq(token.balanceOf(account), initialBalance + amount);
    }
}

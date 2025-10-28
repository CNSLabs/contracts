// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/ShoTokenL1.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract ShoTokenL1Test is Test {
    ShoTokenL1 public token;
    address public owner = address(0x123);
    address public user1 = address(0x456);
    address public user2 = address(0x789);

    uint256 public constant INITIAL_SUPPLY = 100_000_000 * 10 ** 18;

    function setUp() public {
        token = new ShoTokenL1("Canonical CNS Token", "CNS", INITIAL_SUPPLY, owner);
    }

    function testInitialSupply() public view {
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY);
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
    }

    function testTokenMetadata() public view {
        assertEq(token.name(), "Canonical CNS Token");
        assertEq(token.symbol(), "CNS");
        assertEq(token.decimals(), 18);
    }

    function testConstructorZeroRecipient() public {
        vm.expectRevert("recipient=0");
        new ShoTokenL1("Test Token", "TEST", 1000, address(0));
    }

    // Basic ERC20 functionality tests
    function testTransfer() public {
        uint256 transferAmount = 1000 * 10 ** 18;

        vm.prank(owner);
        bool success = token.transfer(user1, transferAmount);

        assertTrue(success);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - transferAmount);
        assertEq(token.balanceOf(user1), transferAmount);
    }

    function testTransferInsufficientBalance() public {
        uint256 transferAmount = INITIAL_SUPPLY + 1;

        vm.prank(owner);
        vm.expectRevert();
        token.transfer(user1, transferAmount);
    }

    function testTransferToZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert();
        token.transfer(address(0), 1000);
    }

    function testApprove() public {
        uint256 approveAmount = 1000 * 10 ** 18;

        vm.prank(owner);
        bool success = token.approve(user1, approveAmount);

        assertTrue(success);
        assertEq(token.allowance(owner, user1), approveAmount);
    }

    function testTransferFrom() public {
        uint256 approveAmount = 1000 * 10 ** 18;

        // Owner approves user1 to spend tokens
        vm.prank(owner);
        token.approve(user1, approveAmount);

        // User1 transfers from owner to user2
        vm.prank(user1);
        bool success = token.transferFrom(owner, user2, approveAmount);

        assertTrue(success);
        assertEq(token.balanceOf(user2), approveAmount);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - approveAmount);
        assertEq(token.allowance(owner, user1), 0);
    }

    function testTransferFromInsufficientAllowance() public {
        vm.prank(user1);
        vm.expectRevert();
        token.transferFrom(owner, user2, 1000);
    }

    // ERC20Permit functionality tests
    function testPermit() public {
        uint256 privateKey = 0x1234567890123456789012345678901234567890123456789012345678901234;
        address signer = vm.addr(privateKey);

        // Create a new token instance with the signer as the initial recipient
        ShoTokenL1 permitToken = new ShoTokenL1("Test CNS Token", "TCNS", 1000 * 10 ** 18, signer);

        uint256 value = 100 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = permitToken.nonces(signer);

        // Create the permit message hash
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                signer,
                user1,
                value,
                nonce,
                deadline
            )
        );

        bytes32 hash = MessageHashUtils.toTypedDataHash(permitToken.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);

        // Execute permit
        permitToken.permit(signer, user1, value, deadline, v, r, s);

        // Verify allowance was set
        assertEq(permitToken.allowance(signer, user1), value);
        assertEq(permitToken.nonces(signer), nonce + 1);
    }

    function testPermitExpired() public {
        uint256 privateKey = 0x1234567890123456789012345678901234567890123456789012345678901234;
        address signer = vm.addr(privateKey);

        ShoTokenL1 permitToken = new ShoTokenL1("Test CNS Token", "TCNS", 1000 * 10 ** 18, signer);

        uint256 value = 100 * 10 ** 18;
        uint256 deadline = block.timestamp - 1; // Expired deadline
        uint256 nonce = permitToken.nonces(signer);

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                signer,
                user1,
                value,
                nonce,
                deadline
            )
        );

        bytes32 hash = MessageHashUtils.toTypedDataHash(permitToken.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);

        vm.expectRevert();
        permitToken.permit(signer, user1, value, deadline, v, r, s);
    }

    function testPermitInvalidSignature() public {
        uint256 privateKey = 0x1234567890123456789012345678901234567890123456789012345678901234;
        address signer = vm.addr(privateKey);

        ShoTokenL1 permitToken = new ShoTokenL1("Test CNS Token", "TCNS", 1000 * 10 ** 18, signer);

        uint256 value = 100 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = permitToken.nonces(signer);

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                signer,
                user1,
                value,
                nonce,
                deadline
            )
        );

        bytes32 hash = MessageHashUtils.toTypedDataHash(permitToken.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);

        // Use wrong signer
        vm.expectRevert();
        permitToken.permit(user1, user1, value, deadline, v, r, s);
    }

    function testPermitReplayAttack() public {
        uint256 privateKey = 0x1234567890123456789012345678901234567890123456789012345678901234;
        address signer = vm.addr(privateKey);

        ShoTokenL1 permitToken = new ShoTokenL1("Test CNS Token", "TCNS", 1000 * 10 ** 18, signer);

        uint256 value = 100 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = permitToken.nonces(signer);

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                signer,
                user1,
                value,
                nonce,
                deadline
            )
        );

        bytes32 hash = MessageHashUtils.toTypedDataHash(permitToken.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);

        // First permit should succeed
        permitToken.permit(signer, user1, value, deadline, v, r, s);

        // Second permit with same signature should fail (replay attack)
        vm.expectRevert();
        permitToken.permit(signer, user1, value, deadline, v, r, s);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "../src/ShoTokenL1.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract ShoTokenL1Test is Test {
    ShoTokenL1 public token;

    // Different addresses for each role
    address public defaultAdmin = address(0x111);
    address public upgrader = address(0x222);
    address public pauser = address(0x333);
    address public allowlistAdmin = address(0x444);
    address public initialRecipient = address(0x555);

    // Test users
    address public user1 = address(0x456);
    address public user2 = address(0x789);

    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 ether; // 1B tokens

    function setUp() public {
        // Deploy implementation
        ShoTokenL1 implementation = new ShoTokenL1();

        // Prepare initialization data with different addresses for each role
        address[] memory emptyAllowlist = new address[](0);
        bytes memory initData = abi.encodeWithSelector(
            ShoTokenL1.initialize.selector,
            defaultAdmin, // defaultAdmin
            upgrader, // upgrader
            pauser, // pauser
            allowlistAdmin, // allowlistAdmin
            initialRecipient, // initialRecipient
            "Canonical SHO Token",
            "SHO",
            emptyAllowlist
        );

        // Deploy proxy with initialization
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        token = ShoTokenL1(address(proxy));
    }

    function testInitialSupply() public view {
        assertEq(token.balanceOf(initialRecipient), INITIAL_SUPPLY);
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
    }

    function testTokenMetadata() public view {
        assertEq(token.name(), "Canonical SHO Token");
        assertEq(token.symbol(), "SHO");
        assertEq(token.decimals(), 18);
    }

    function testInitializeZeroRecipient() public {
        ShoTokenL1 impl = new ShoTokenL1();
        address[] memory emptyAllowlist = new address[](0);
        bytes memory initData = abi.encodeWithSelector(
            ShoTokenL1.initialize.selector,
            defaultAdmin,
            upgrader,
            pauser,
            allowlistAdmin,
            address(0), // zero recipient should revert
            "Test Token",
            "TEST",
            emptyAllowlist
        );

        vm.expectRevert(ShoTokenL1.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    // Basic ERC20 functionality tests
    function testTransfer() public {
        uint256 transferAmount = 1000 * 10 ** 18;

        // Allowlist initialRecipient so they can transfer
        vm.prank(allowlistAdmin);
        token.setTransferFromAllowed(initialRecipient, true);

        vm.prank(initialRecipient);
        bool success = token.transfer(user1, transferAmount);

        assertTrue(success);
        assertEq(token.balanceOf(initialRecipient), INITIAL_SUPPLY - transferAmount);
        assertEq(token.balanceOf(user1), transferAmount);
    }

    function testTransferInsufficientBalance() public {
        uint256 transferAmount = INITIAL_SUPPLY + 1;

        vm.prank(initialRecipient);
        vm.expectRevert();
        token.transfer(user1, transferAmount);
    }

    function testTransferToZeroAddress() public {
        vm.prank(initialRecipient);
        vm.expectRevert();
        token.transfer(address(0), 1000);
    }

    function testApprove() public {
        uint256 approveAmount = 1000 * 10 ** 18;

        vm.prank(initialRecipient);
        bool success = token.approve(user1, approveAmount);

        assertTrue(success);
        assertEq(token.allowance(initialRecipient, user1), approveAmount);
    }

    function testTransferFrom() public {
        uint256 approveAmount = 1000 * 10 ** 18;

        // Allowlist both initialRecipient and user1 so they can transfer
        vm.prank(allowlistAdmin);
        token.setTransferFromAllowed(initialRecipient, true);
        vm.prank(allowlistAdmin);
        token.setTransferFromAllowed(user1, true);

        // Initial recipient approves user1 to spend tokens
        vm.prank(initialRecipient);
        token.approve(user1, approveAmount);

        // User1 transfers from initialRecipient to user2
        vm.prank(user1);
        bool success = token.transferFrom(initialRecipient, user2, approveAmount);

        assertTrue(success);
        assertEq(token.balanceOf(user2), approveAmount);
        assertEq(token.balanceOf(initialRecipient), INITIAL_SUPPLY - approveAmount);
        assertEq(token.allowance(initialRecipient, user1), 0);
    }

    function testTransferFromInsufficientAllowance() public {
        // Allowlist user1 so they can attempt transfer
        vm.prank(allowlistAdmin);
        token.setTransferFromAllowed(user1, true);

        vm.prank(user1);
        vm.expectRevert();
        token.transferFrom(initialRecipient, user2, 1000);
    }

    // ERC20Permit functionality tests
    function testPermit() public {
        uint256 privateKey = 0x1234567890123456789012345678901234567890123456789012345678901234;
        address signer = vm.addr(privateKey);

        // Create a new token instance with different addresses for each role
        ShoTokenL1 impl = new ShoTokenL1();
        address[] memory emptyAllowlist = new address[](0);
        bytes memory initData = abi.encodeWithSelector(
            ShoTokenL1.initialize.selector,
            defaultAdmin,
            upgrader,
            pauser,
            allowlistAdmin,
            signer, // signer is the initial recipient for permit tests
            "Test SHO Token",
            "TSHO",
            emptyAllowlist
        );
        ERC1967Proxy permitProxy = new ERC1967Proxy(address(impl), initData);
        ShoTokenL1 permitToken = ShoTokenL1(address(permitProxy));

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

        ShoTokenL1 impl = new ShoTokenL1();
        address[] memory emptyAllowlist = new address[](0);
        bytes memory initData = abi.encodeWithSelector(
            ShoTokenL1.initialize.selector,
            defaultAdmin,
            upgrader,
            pauser,
            allowlistAdmin,
            signer, // signer is the initial recipient for permit tests
            "Test SHO Token",
            "TSHO",
            emptyAllowlist
        );
        ERC1967Proxy permitProxy = new ERC1967Proxy(address(impl), initData);
        ShoTokenL1 permitToken = ShoTokenL1(address(permitProxy));

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

        ShoTokenL1 impl = new ShoTokenL1();
        address[] memory emptyAllowlist = new address[](0);
        bytes memory initData = abi.encodeWithSelector(
            ShoTokenL1.initialize.selector,
            defaultAdmin,
            upgrader,
            pauser,
            allowlistAdmin,
            signer, // signer is the initial recipient for permit tests
            "Test SHO Token",
            "TSHO",
            emptyAllowlist
        );
        ERC1967Proxy permitProxy = new ERC1967Proxy(address(impl), initData);
        ShoTokenL1 permitToken = ShoTokenL1(address(permitProxy));

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

        ShoTokenL1 impl = new ShoTokenL1();
        address[] memory emptyAllowlist = new address[](0);
        bytes memory initData = abi.encodeWithSelector(
            ShoTokenL1.initialize.selector,
            defaultAdmin,
            upgrader,
            pauser,
            allowlistAdmin,
            signer, // signer is the initial recipient for permit tests
            "Test SHO Token",
            "TSHO",
            emptyAllowlist
        );
        ERC1967Proxy permitProxy = new ERC1967Proxy(address(impl), initData);
        ShoTokenL1 permitToken = ShoTokenL1(address(permitProxy));

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

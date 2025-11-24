// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "../src/ShoTokenL1.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

// Re-declare OZ AccessControl custom error for selector-precise revert checks
error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);
// Re-declare Pausable custom error for selector-precise revert checks
error EnforcedPause();
// Re-declare Initializable custom error for selector-precise revert checks
error InvalidInitialization();
// Local copy of ShoTokenL1 Initialized event signature for expectEmit matching
event Initialized(address indexed admin, address indexed initialRecipient, string name, string symbol);

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

    /* ============================================================= */
    /* ===================== ACCESS CONTROL TESTS ================== */
    /* ============================================================= */

    function testInitialRoleAssignmentsAndAdmins() public view {
        // Role admins are DEFAULT_ADMIN_ROLE
        assertEq(token.getRoleAdmin(token.PAUSER_ROLE()), token.DEFAULT_ADMIN_ROLE());
        assertEq(token.getRoleAdmin(token.ALLOWLIST_ADMIN_ROLE()), token.DEFAULT_ADMIN_ROLE());
        assertEq(token.getRoleAdmin(token.UPGRADER_ROLE()), token.DEFAULT_ADMIN_ROLE());

        // Initial role holders
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(token.hasRole(token.PAUSER_ROLE(), pauser));
        assertTrue(token.hasRole(token.PAUSER_ROLE(), defaultAdmin)); // backup grant
        assertTrue(token.hasRole(token.ALLOWLIST_ADMIN_ROLE(), allowlistAdmin));
        assertTrue(token.hasRole(token.ALLOWLIST_ADMIN_ROLE(), defaultAdmin)); // backup grant
        assertTrue(token.hasRole(token.UPGRADER_ROLE(), upgrader));
    }

    function testDefaultAdminCanGrantAndRevokePauserRole() public {
        bytes32 PAUSER = token.PAUSER_ROLE();

        // Grant PAUSER_ROLE to user1
        vm.startPrank(defaultAdmin);
        token.grantRole(PAUSER, user1);
        vm.stopPrank();
        assertTrue(token.hasRole(PAUSER, user1));

        // user1 can pause/unpause
        vm.startPrank(user1);
        token.pause();
        token.unpause();
        vm.stopPrank();

        // Revoke and ensure no longer authorized
        vm.startPrank(defaultAdmin);
        token.revokeRole(PAUSER, user1);
        vm.stopPrank();
        assertFalse(token.hasRole(PAUSER, user1));

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, PAUSER));
        token.pause();
        vm.stopPrank();
    }

    function testNonAdminCannotGrantRoles() public {
        bytes32 DEFAULT_ADMIN = token.DEFAULT_ADMIN_ROLE();
        bytes32 PAUSER = token.PAUSER_ROLE();

        // Non-admin attempting to grant PAUSER_ROLE should revert with needed DEFAULT_ADMIN_ROLE
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, DEFAULT_ADMIN));
        token.grantRole(PAUSER, user2);
        vm.stopPrank();
    }

    function testPauserAndDefaultAdminCanPauseUnpause() public {
        // pauser can pause/unpause
        vm.prank(pauser);
        token.pause();
        vm.prank(pauser);
        token.unpause();

        // defaultAdmin (backup PAUSER_ROLE) can pause/unpause
        vm.prank(defaultAdmin);
        token.pause();
        vm.prank(defaultAdmin);
        token.unpause();
    }

    function testNonPauserCannotPause() public {
        bytes32 PAUSER = token.PAUSER_ROLE();
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, PAUSER));
        token.pause();
        vm.stopPrank();
    }

    function testAllowlistEditingAccessControlledSingle() public {
        bytes32 ALLOWLIST = token.ALLOWLIST_ADMIN_ROLE();

        // allowlistAdmin can edit
        vm.prank(allowlistAdmin);
        token.setTransferFromAllowed(user1, true);

        // defaultAdmin (backup allowlist admin) can edit
        vm.prank(defaultAdmin);
        token.setTransferFromAllowed(user2, true);

        // others cannot
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, ALLOWLIST));
        token.setTransferFromAllowed(user1, false);
        vm.stopPrank();
    }

    function testAllowlistEditingAccessControlledBatchAndToggle() public {
        bytes32 ALLOWLIST = token.ALLOWLIST_ADMIN_ROLE();
        address[] memory accounts = new address[](2);
        accounts[0] = user1;
        accounts[1] = user2;

        // allowlistAdmin can batch edit
        vm.prank(allowlistAdmin);
        token.setTransferFromAllowedBatch(accounts, true);

        // defaultAdmin can toggle allowlist
        vm.prank(defaultAdmin);
        token.setTransferFromAllowlistEnabled(false);

        // others cannot batch edit or toggle
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, ALLOWLIST));
        token.setTransferFromAllowedBatch(accounts, false);
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user2, ALLOWLIST));
        token.setTransferFromAllowlistEnabled(true);
        vm.stopPrank();
    }

    function testAdminCanGrantAndRevokeAllowlistAdminRole() public {
        bytes32 ALLOWLIST = token.ALLOWLIST_ADMIN_ROLE();

        // Grant ALLOWLIST_ADMIN_ROLE to user1
        vm.startPrank(defaultAdmin);
        token.grantRole(ALLOWLIST, user1);
        vm.stopPrank();
        assertTrue(token.hasRole(ALLOWLIST, user1));

        // user1 can now toggle allowlist
        vm.startPrank(user1);
        token.setTransferFromAllowlistEnabled(true);
        vm.stopPrank();

        // Revoke role and verify user1 loses permission
        vm.startPrank(defaultAdmin);
        token.revokeRole(ALLOWLIST, user1);
        vm.stopPrank();
        assertFalse(token.hasRole(ALLOWLIST, user1));

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, ALLOWLIST));
        token.setTransferFromAllowed(user2, true);
        vm.stopPrank();
    }

    /* ============================================================= */
    /* =================== INIT AND DEFAULTS TESTS ================= */
    /* ============================================================= */

    function testInitializeZeroDefaultAdmin() public {
        ShoTokenL1 impl = new ShoTokenL1();
        address[] memory empty = new address[](0);
        bytes memory initData = abi.encodeWithSelector(
            ShoTokenL1.initialize.selector,
            address(0), // defaultAdmin zero
            upgrader,
            pauser,
            allowlistAdmin,
            initialRecipient,
            "Canonical SHO Token",
            "SHO",
            empty
        );
        vm.expectRevert(ShoTokenL1.InvalidDefaultAdmin.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function testInitializeZeroUpgrader() public {
        ShoTokenL1 impl = new ShoTokenL1();
        address[] memory empty = new address[](0);
        bytes memory initData = abi.encodeWithSelector(
            ShoTokenL1.initialize.selector,
            defaultAdmin,
            address(0), // upgrader zero
            pauser,
            allowlistAdmin,
            initialRecipient,
            "Canonical SHO Token",
            "SHO",
            empty
        );
        vm.expectRevert(ShoTokenL1.InvalidUpgrader.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function testInitializeZeroPauser() public {
        ShoTokenL1 impl = new ShoTokenL1();
        address[] memory empty = new address[](0);
        bytes memory initData = abi.encodeWithSelector(
            ShoTokenL1.initialize.selector,
            defaultAdmin,
            upgrader,
            address(0), // pauser zero
            allowlistAdmin,
            initialRecipient,
            "Canonical SHO Token",
            "SHO",
            empty
        );
        vm.expectRevert(ShoTokenL1.InvalidPauser.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function testInitializeZeroAllowlistAdmin() public {
        ShoTokenL1 impl = new ShoTokenL1();
        address[] memory empty = new address[](0);
        bytes memory initData = abi.encodeWithSelector(
            ShoTokenL1.initialize.selector,
            defaultAdmin,
            upgrader,
            pauser,
            address(0), // allowlist admin zero
            initialRecipient,
            "Canonical SHO Token",
            "SHO",
            empty
        );
        vm.expectRevert(ShoTokenL1.InvalidAllowlistAdmin.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function testReinitializeReverts() public {
        // Attempt to initialize again should revert with InvalidInitialization
        address[] memory empty = new address[](0);
        vm.startPrank(defaultAdmin);
        vm.expectRevert(InvalidInitialization.selector);
        token.initialize(
            defaultAdmin, upgrader, pauser, allowlistAdmin, initialRecipient, "Canonical SHO Token", "SHO", empty
        );
        vm.stopPrank();
    }

    function testInitializedEventEmittedOnDeploy() public {
        ShoTokenL1 impl = new ShoTokenL1();
        address[] memory empty = new address[](0);

        // Expect the ShoTokenL1 Initialized event (not the OZ Initializable one)
        vm.expectEmit(true, true, true, true);
        emit Initialized(defaultAdmin, initialRecipient, "Canonical SHO Token", "SHO");

        bytes memory initData = abi.encodeWithSelector(
            ShoTokenL1.initialize.selector,
            defaultAdmin,
            upgrader,
            pauser,
            allowlistAdmin,
            initialRecipient,
            "Canonical SHO Token",
            "SHO",
            empty
        );
        new ERC1967Proxy(address(impl), initData);
    }

    function testDefaultAllowlistDefaults() public view {
        // Contract itself and default admin should be allowlisted by default; allowlist enabled by default
        assertTrue(token.transferFromAllowlistEnabled());
        assertTrue(token.isTransferFromAllowlisted(address(token)));
        assertTrue(token.isTransferFromAllowlisted(defaultAdmin));
    }

    /* ============================================================= */
    /* ===================== PAUSABLE BEHAVIOR ===================== */
    /* ============================================================= */

    function testTransfersRevertWithEnforcedPauseApprovePermitSucceed() public {
        // Make from and spender allowlisted to avoid allowlist errors masking pause errors
        vm.prank(allowlistAdmin);
        token.setTransferFromAllowed(initialRecipient, true);
        vm.prank(allowlistAdmin);
        token.setTransferFromAllowed(user1, true);

        // Pause
        vm.prank(pauser);
        token.pause();

        // transfer reverts with EnforcedPause
        vm.startPrank(initialRecipient);
        vm.expectRevert(EnforcedPause.selector);
        token.transfer(user1, 1 ether);
        vm.stopPrank();

        // Approve still succeeds while paused
        vm.prank(initialRecipient);
        assertTrue(token.approve(user1, 2 ether));

        // transferFrom reverts with EnforcedPause even with allowance
        vm.startPrank(user1);
        vm.expectRevert(EnforcedPause.selector);
        token.transferFrom(initialRecipient, user2, 1 ether);
        vm.stopPrank();

        // Permit still succeeds while paused: deploy fresh token for clean signer setup, pause, then permit
        ShoTokenL1 impl = new ShoTokenL1();
        address[] memory emptyAllowlist = new address[](0);
        uint256 privateKey = 0xabc;
        address signer = vm.addr(privateKey);
        bytes memory initData = abi.encodeWithSelector(
            ShoTokenL1.initialize.selector,
            defaultAdmin,
            upgrader,
            pauser,
            allowlistAdmin,
            signer,
            "Paused Permit",
            "PP",
            emptyAllowlist
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        ShoTokenL1 pausedToken = ShoTokenL1(address(proxy));
        vm.prank(pauser);
        pausedToken.pause();

        uint256 value = 5 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = pausedToken.nonces(signer);
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
        bytes32 hash = MessageHashUtils.toTypedDataHash(pausedToken.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        pausedToken.permit(signer, user1, value, deadline, v, r, s);
        assertEq(pausedToken.allowance(signer, user1), value);
    }

    /* ============================================================= */
    /* ================= ALLOWLIST SEMANTICS & LIMITS ============== */
    /* ============================================================= */

    function testSenderNotAllowlistedRevertsSpecific() public {
        // Non-allowlisted user should revert while allowlist is enabled by default
        vm.startPrank(user1);
        vm.expectRevert(ShoTokenL1.TransferFromNotAllowlisted.selector);
        token.transfer(user2, 1);
        vm.stopPrank();
    }

    function testAllowlistToggleAffectsTransfers() public {
        // Fund a non-allowlisted sender (user1) from an allowlisted address (initialRecipient)
        vm.prank(initialRecipient);
        token.transfer(user1, 1 ether);
        assertEq(token.balanceOf(user1), 1 ether);

        // Disable allowlist: user1 (non-allowlisted) can transfer
        vm.prank(allowlistAdmin);
        token.setTransferFromAllowlistEnabled(false);
        vm.prank(user1);
        token.transfer(user2, 0.5 ether);
        assertEq(token.balanceOf(user2), 0.5 ether);

        // Re-enable: user1 transfers should revert
        vm.prank(allowlistAdmin);
        token.setTransferFromAllowlistEnabled(true);
        vm.startPrank(user1);
        vm.expectRevert(ShoTokenL1.TransferFromNotAllowlisted.selector);
        token.transfer(user2, 1);
        vm.stopPrank();
    }

    function testSetSenderAllowedZeroAddressReverts() public {
        vm.startPrank(allowlistAdmin);
        vm.expectRevert(ShoTokenL1.ZeroAddress.selector);
        token.setTransferFromAllowed(address(0), true);
        vm.stopPrank();
    }

    function testSetSenderAllowedBatchEmptyReverts() public {
        address[] memory empty = new address[](0);
        vm.startPrank(allowlistAdmin);
        vm.expectRevert(ShoTokenL1.EmptyBatch.selector);
        token.setTransferFromAllowedBatch(empty, true);
        vm.stopPrank();
    }

    function testSetSenderAllowedBatchTooLargeReverts() public {
        uint256 size = token.MAX_BATCH_SIZE() + 1;
        address[] memory big = new address[](size);
        for (uint256 i; i < size; ++i) {
            big[i] = address(uint160(i + 1));
        }
        vm.startPrank(allowlistAdmin);
        vm.expectRevert(ShoTokenL1.BatchTooLarge.selector);
        token.setTransferFromAllowedBatch(big, true);
        vm.stopPrank();
    }

    function testSetSenderAllowedBatchWithZeroAddressReverts() public {
        address[] memory accounts = new address[](3);
        accounts[0] = user1;
        accounts[1] = address(0);
        accounts[2] = user2;
        vm.startPrank(allowlistAdmin);
        vm.expectRevert(ShoTokenL1.ZeroAddress.selector);
        token.setTransferFromAllowedBatch(accounts, true);
        vm.stopPrank();
    }

    function testBatchEventsEmitted() public {
        address[] memory accounts = new address[](2);
        accounts[0] = user1;
        accounts[1] = user2;

        // Expect per-item updates and a final batch update
        vm.expectEmit(true, true, true, true);
        emit ShoTokenL1.TransferFromAllowlistUpdated(user1, true);
        vm.expectEmit(true, true, true, true);
        emit ShoTokenL1.TransferFromAllowlistUpdated(user2, true);
        vm.expectEmit(true, true, true, true);
        emit ShoTokenL1.TransferFromAllowlistBatchUpdated(accounts, true);

        vm.prank(allowlistAdmin);
        token.setTransferFromAllowedBatch(accounts, true);
    }

    function testToggleEventEmitted() public {
        vm.expectEmit(true, true, true, true);
        emit ShoTokenL1.TransferFromAllowlistEnabledUpdated(false);
        vm.prank(allowlistAdmin);
        token.setTransferFromAllowlistEnabled(false);
    }

    /* ============================================================= */
    /* ================= TRANSFER FROM EDGE CASES ================== */
    /* ============================================================= */

    function testSpenderAllowlistedOwnerNot_reverts() public {
        // Allowlist spender only
        vm.prank(allowlistAdmin);
        token.setTransferFromAllowed(user1, true);
        // Ensure owner (from) is NOT allowlisted
        vm.prank(allowlistAdmin);
        token.setTransferFromAllowed(initialRecipient, false);
        // Approve
        vm.prank(initialRecipient);
        token.approve(user1, 1 ether);
        // TransferFrom should revert because from is not allowlisted
        vm.startPrank(user1);
        vm.expectRevert(ShoTokenL1.TransferFromNotAllowlisted.selector);
        token.transferFrom(initialRecipient, user2, 1 ether);
        vm.stopPrank();
    }

    function testOwnerAllowlistedSpenderNot_succeeds() public {
        // Allowlist owner only
        vm.prank(allowlistAdmin);
        token.setTransferFromAllowed(initialRecipient, true);
        // Approve
        vm.prank(initialRecipient);
        token.approve(user1, 1 ether);
        // TransferFrom should succeed because allowlist checks the from
        vm.prank(user1);
        token.transferFrom(initialRecipient, user2, 1 ether);
        assertEq(token.balanceOf(user2), 1 ether);
    }

    function testTransferFromBothNotAllowlisted_succeedsWhenAllowlistDisabled() public {
        // Disable allowlist
        vm.prank(allowlistAdmin);
        token.setTransferFromAllowlistEnabled(false);
        // Approve
        vm.prank(initialRecipient);
        token.approve(user1, 1 ether);
        // TransferFrom should succeed
        vm.prank(user1);
        token.transferFrom(initialRecipient, user2, 1 ether);
        assertEq(token.balanceOf(user2), 1 ether);
    }

    /* ============================================================= */
    /* ===================== UPGRADE AUTH CHECKS =================== */
    /* ============================================================= */

    function testNonUpgraderCannotUpgrade() public {
        // Use any address as new implementation; authorization check happens first
        address newImpl = address(new ShoTokenL1());
        bytes32 UPGRADER = token.UPGRADER_ROLE();

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, UPGRADER));
        token.upgradeToAndCall(newImpl, "");
        vm.stopPrank();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/ShoTokenL2.sol";
import "../src/ShoTokenL2V2.sol";

contract ShoTokenL2V2Test is Test {
    ShoTokenL2 public tokenV1;
    ShoTokenL2V2 public tokenV2;
    ERC1967Proxy public proxy;

    address public admin;
    address public bridge;
    address public l1Token;
    address public user1;
    address public user2;

    string constant TOKEN_NAME = "CNS Linea Token";
    string constant TOKEN_SYMBOL = "CNSL";
    uint8 constant DECIMALS = 18;

    event SenderAllowlistUpdated(address indexed account, bool allowed);

    function setUp() public {
        admin = makeAddr("admin");
        // Deploy a mock bridge contract
        MockBridge mockBridge = new MockBridge();
        bridge = address(mockBridge);
        l1Token = makeAddr("l1Token");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy V1 implementation
        tokenV1 = new ShoTokenL2();

        // Prepare initialization data
        address[] memory emptyAllowlist = new address[](0);
        bytes memory initData = abi.encodeWithSelector(
            ShoTokenL2.initialize.selector,
            admin,
            admin,
            admin,
            admin,
            bridge,
            l1Token,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            DECIMALS,
            emptyAllowlist
        );

        // Deploy proxy with V1 implementation
        proxy = new ERC1967Proxy(address(tokenV1), initData);
    }

    function test_UpgradeToV2() public {
        // Deploy V2 implementation
        tokenV2 = new ShoTokenL2V2();

        // Upgrade to V2
        bytes memory initV2Data = abi.encodeWithSelector(ShoTokenL2V2.initializeV2.selector);

        vm.prank(admin);
        ShoTokenL2V2(address(proxy)).upgradeToAndCall(address(tokenV2), initV2Data);

        // Verify upgrade
        ShoTokenL2V2 upgradedProxy = ShoTokenL2V2(address(proxy));
        assertEq(upgradedProxy.name(), TOKEN_NAME);
        assertEq(upgradedProxy.symbol(), TOKEN_SYMBOL);
        assertEq(upgradedProxy.decimals(), DECIMALS);
    }

    function test_VotingFunctionalityAfterUpgrade() public {
        // Upgrade to V2
        tokenV2 = new ShoTokenL2V2();
        bytes memory initV2Data = abi.encodeWithSelector(ShoTokenL2V2.initializeV2.selector);

        vm.prank(admin);
        ShoTokenL2V2(address(proxy)).upgradeToAndCall(address(tokenV2), initV2Data);

        ShoTokenL2V2 upgradedProxy = ShoTokenL2V2(address(proxy));

        // Add users to allowlist
        vm.startPrank(admin);
        upgradedProxy.setSenderAllowed(user1, true);
        upgradedProxy.setSenderAllowed(user2, true);
        vm.stopPrank();

        // Mint some tokens via bridge
        uint256 mintAmount = 1000 * 10 ** DECIMALS;
        vm.prank(bridge);
        upgradedProxy.mint(user1, mintAmount);

        // Verify initial state - user has tokens but no voting power (needs to delegate)
        assertEq(upgradedProxy.balanceOf(user1), mintAmount);
        assertEq(upgradedProxy.getVotes(user1), 0);

        // User1 delegates to themselves
        vm.prank(user1);
        upgradedProxy.delegate(user1);

        // Verify voting power after delegation
        assertEq(upgradedProxy.getVotes(user1), mintAmount);

        // User1 delegates to user2
        vm.prank(user1);
        upgradedProxy.delegate(user2);

        // Verify voting power transfer
        assertEq(upgradedProxy.getVotes(user1), 0);
        assertEq(upgradedProxy.getVotes(user2), mintAmount);
    }

    function test_V2MaintainsV1Functionality() public {
        // Upgrade to V2
        tokenV2 = new ShoTokenL2V2();
        bytes memory initV2Data = abi.encodeWithSelector(ShoTokenL2V2.initializeV2.selector);

        vm.prank(admin);
        ShoTokenL2V2(address(proxy)).upgradeToAndCall(address(tokenV2), initV2Data);

        ShoTokenL2V2 upgradedProxy = ShoTokenL2V2(address(proxy));

        // Test pause functionality
        vm.prank(admin);
        upgradedProxy.pause();
        assertTrue(upgradedProxy.paused());

        vm.prank(admin);
        upgradedProxy.unpause();
        assertFalse(upgradedProxy.paused());

        // Test allowlist functionality
        assertFalse(upgradedProxy.isSenderAllowlisted(user1));

        vm.prank(admin);
        upgradedProxy.setSenderAllowed(user1, true);
        assertTrue(upgradedProxy.isSenderAllowlisted(user1));

        // Test batch allowlist
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        vm.prank(admin);
        upgradedProxy.setSenderAllowedBatch(users, true);
        assertTrue(upgradedProxy.isSenderAllowlisted(user1));
        assertTrue(upgradedProxy.isSenderAllowlisted(user2));
    }

    function test_AllowlistStillEnforced() public {
        // Upgrade to V2
        tokenV2 = new ShoTokenL2V2();
        bytes memory initV2Data = abi.encodeWithSelector(ShoTokenL2V2.initializeV2.selector);

        vm.prank(admin);
        ShoTokenL2V2(address(proxy)).upgradeToAndCall(address(tokenV2), initV2Data);

        ShoTokenL2V2 upgradedProxy = ShoTokenL2V2(address(proxy));

        // Add user1 to sender allowlist only
        vm.prank(admin);
        upgradedProxy.setSenderAllowed(user1, true);

        // Mint tokens to user1
        uint256 mintAmount = 1000 * 10 ** DECIMALS;
        vm.prank(bridge);
        upgradedProxy.mint(user1, mintAmount);

        // Transfer to user2 (not allowlisted as sender) - should succeed now
        vm.prank(user1);
        upgradedProxy.transfer(user2, 100 * 10 ** DECIMALS);

        assertEq(upgradedProxy.balanceOf(user2), 100 * 10 ** DECIMALS);
    }

    function test_VotePowerTracksTransfers() public {
        // Upgrade to V2
        tokenV2 = new ShoTokenL2V2();
        bytes memory initV2Data = abi.encodeWithSelector(ShoTokenL2V2.initializeV2.selector);

        vm.prank(admin);
        ShoTokenL2V2(address(proxy)).upgradeToAndCall(address(tokenV2), initV2Data);

        ShoTokenL2V2 upgradedProxy = ShoTokenL2V2(address(proxy));

        // Add users to allowlist
        vm.startPrank(admin);
        upgradedProxy.setSenderAllowed(user1, true);
        upgradedProxy.setSenderAllowed(user2, true);
        vm.stopPrank();

        // Mint tokens to user1
        uint256 mintAmount = 1000 * 10 ** DECIMALS;
        vm.prank(bridge);
        upgradedProxy.mint(user1, mintAmount);

        // Both users delegate to themselves
        vm.prank(user1);
        upgradedProxy.delegate(user1);

        vm.prank(user2);
        upgradedProxy.delegate(user2);

        // Verify initial voting power
        assertEq(upgradedProxy.getVotes(user1), mintAmount);
        assertEq(upgradedProxy.getVotes(user2), 0);

        // Transfer tokens
        uint256 transferAmount = 300 * 10 ** DECIMALS;
        vm.prank(user1);
        upgradedProxy.transfer(user2, transferAmount);

        // Verify voting power updated
        assertEq(upgradedProxy.getVotes(user1), mintAmount - transferAmount);
        assertEq(upgradedProxy.getVotes(user2), transferAmount);
    }

    function test_ClockModeIsBlock() public {
        // Upgrade to V2
        tokenV2 = new ShoTokenL2V2();
        bytes memory initV2Data = abi.encodeWithSelector(ShoTokenL2V2.initializeV2.selector);

        vm.prank(admin);
        ShoTokenL2V2(address(proxy)).upgradeToAndCall(address(tokenV2), initV2Data);

        ShoTokenL2V2 upgradedProxy = ShoTokenL2V2(address(proxy));

        // ERC20Votes uses block.number by default
        assertEq(upgradedProxy.clock(), block.number);
        assertEq(upgradedProxy.CLOCK_MODE(), "mode=blocknumber&from=default");
    }
}

// Mock bridge contract for testing
contract MockBridge {
    // Empty contract that just needs to exist

    }

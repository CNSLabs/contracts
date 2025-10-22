// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {CNSTokenL2} from "../src/CNSTokenL2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Mock bridge contract for testing
contract MockBridge {
    // Empty contract that just needs to exist

    }

contract CNSTokenL2SecurityTestDebug is Test {
    CNSTokenL2 internal token;
    MockBridge internal bridge;
    address internal admin;
    address internal l1Token;
    address internal attacker;

    string constant NAME = "CNS Token L2";
    string constant SYMBOL = "CNS";
    uint8 constant DECIMALS = 18;

    function setUp() public {
        admin = makeAddr("admin");
        bridge = new MockBridge();
        l1Token = makeAddr("l1Token");
        attacker = makeAddr("attacker");

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

    function testDebugRoles() public {
        console.log("Admin address:", admin);
        console.log("Attacker address:", attacker);

        console.log("DEFAULT_ADMIN_ROLE constant:", uint256(token.DEFAULT_ADMIN_ROLE()));
        console.log("PAUSER_ROLE constant:", uint256(token.PAUSER_ROLE()));

        console.log("Admin has DEFAULT_ADMIN_ROLE:", token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        console.log("Attacker has DEFAULT_ADMIN_ROLE:", token.hasRole(token.DEFAULT_ADMIN_ROLE(), attacker));

        console.log("Admin has PAUSER_ROLE:", token.hasRole(token.PAUSER_ROLE(), admin));
        console.log("Attacker has PAUSER_ROLE:", token.hasRole(token.PAUSER_ROLE(), attacker));

        // Test if admin can pause (should work)
        vm.prank(admin);
        token.pause();
        console.log("Contract paused:", token.paused());

        // Test if admin can unpause (should work)
        vm.prank(admin);
        token.unpause();
        console.log("Contract paused after unpause:", token.paused());

        // Test if admin can grant roles (should work)
        vm.prank(admin);
        token.grantRole(token.PAUSER_ROLE(), attacker);
        console.log("After granting - Attacker has PAUSER_ROLE:", token.hasRole(token.PAUSER_ROLE(), attacker));
    }
}

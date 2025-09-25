// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/CNSTokenL1.sol";

contract CNSTokenL1Test is Test {
    CNSTokenL1 public token;
    address public owner = address(0x123);
    address public user1 = address(0x456);
    address public user2 = address(0x789);

    function setUp() public {
        token = new CNSTokenL1(owner);
    }

    function testInitialSupply() public {
        assertEq(token.balanceOf(owner), 100_000_000 * 10 ** 18);
        assertEq(token.totalSupply(), 100_000_000 * 10 ** 18);
    }

    function testMintByOwner() public {
        vm.prank(owner);
        token.mint(user1, 1000 * 10 ** 18);

        assertEq(token.balanceOf(user1), 1000 * 10 ** 18);
        assertEq(token.totalSupply(), 100_000_000 * 10 ** 18 + 1000 * 10 ** 18);
    }

    function testMintByBridge() public {
        address bridge = address(0x999);
        vm.prank(owner);
        token.setBridgeContract(bridge);

        vm.prank(bridge);
        token.mint(user1, 1000 * 10 ** 18);

        assertEq(token.balanceOf(user1), 1000 * 10 ** 18);
    }

    function testCannotMintUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert("CNSTokenL1: caller is not bridge or owner");
        token.mint(user2, 1000 * 10 ** 18);
    }

    function testMaxSupply() public {
        vm.startPrank(owner);
        token.mint(user1, token.MAX_SUPPLY() - token.totalSupply());

        vm.expectRevert("CNSTokenL1: max supply exceeded");
        token.mint(user2, 1);
        vm.stopPrank();
    }

    function testBurn() public {
        vm.prank(owner);
        token.mint(user1, 1000 * 10 ** 18);

        vm.prank(owner);
        token.burn(500 * 10 ** 18);

        assertEq(token.balanceOf(owner), 100_000_000 * 10 ** 18 - 500 * 10 ** 18);
        assertEq(token.totalSupply(), 100_000_000 * 10 ** 18 + 500 * 10 ** 18);
    }

    function testSetBridgeContract() public {
        address newBridge = address(0x999);

        vm.prank(owner);
        token.setBridgeContract(newBridge);

        assertEq(token.l1Bridge(), newBridge);
    }

    function testSetMinter() public {
        address newMinter = address(0x888);

        vm.prank(owner);
        token.setMinter(newMinter);

        assertEq(token.minter(), newMinter);
    }

    function testPauseUnpause() public {
        vm.prank(owner);
        token.pause();

        assertEq(token.paused(), true);

        vm.prank(owner);
        token.unpause();

        assertEq(token.paused(), false);
    }

    function testTransferWhenPaused() public {
        vm.prank(owner);
        token.mint(user1, 1000 * 10 ** 18);

        vm.prank(owner);
        token.pause();

        vm.prank(user1);
        vm.expectRevert();
        token.transfer(user2, 100 * 10 ** 18);
    }
}

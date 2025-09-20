// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/CNSTokenSale.sol";
import "../src/CNSTokenL2.sol";
import "../src/CNSAccessNFT.sol";
import "../src/CNSTierProgression.sol";

contract CNSTokenSaleTest is Test {
    CNSTokenSale public tokenSale;
    CNSTokenL2 public tokenL2;
    CNSAccessNFT public accessNFT;
    CNSTierProgression public tierProgression;

    address public owner = address(0x123);
    address public user1 = address(0x456);
    address public user2 = address(0x789);

    function setUp() public {
        // Deploy contracts
        tokenL2 = new CNSTokenL2(owner, address(0x123)); // Mock L1 token
        accessNFT = new CNSAccessNFT(owner, "https://api.cns.com/nft/");
        tierProgression = new CNSTierProgression(owner, address(accessNFT));

        tokenSale = new CNSTokenSale(
            address(tokenL2),
            address(accessNFT),
            address(tierProgression),
            owner
        );

        // Mint tokens to sale contract
        vm.prank(owner);
        tokenL2.mint(address(tokenSale), 100000000 * 10**18);

        // Set up sale
        vm.prank(owner);
        tokenSale.setWhitelist(user1, true);
    }

    function testCalculateTokenAmount() public {
        uint256 ethAmount = 1 ether;
        uint256 expectedTokens = (ethAmount * 10**18) / tokenSale.tokenPrice();

        assertEq(tokenSale.calculateTokenAmount(ethAmount), expectedTokens);
    }

    function testCalculateEthCost() public {
        uint256 tokenAmount = 1000 * 10**18;
        uint256 expectedCost = (tokenAmount * tokenSale.tokenPrice()) / 10**18;

        assertEq(tokenSale.calculateEthCost(tokenAmount), expectedCost);
    }

    function testPurchaseTokensWhitelisted() public {
        uint256 ethAmount = 1 ether;
        uint256 expectedTokens = tokenSale.calculateTokenAmount(ethAmount);

        vm.prank(user1);
        tokenSale.purchaseTokens{value: ethAmount}();

        assertEq(tokenSale.userPurchases(user1), expectedTokens);
        assertEq(tokenSale.tokensSold(), expectedTokens);
        assertEq(tokenL2.balanceOf(user1), expectedTokens);
    }

    function testPurchaseExactTokens() public {
        uint256 tokenAmount = 1000 * 10**18;
        uint256 ethCost = tokenSale.calculateEthCost(tokenAmount);

        vm.prank(user1);
        tokenSale.purchaseExactTokens{value: ethCost}(tokenAmount);

        assertEq(tokenSale.userPurchases(user1), tokenAmount);
        assertEq(tokenL2.balanceOf(user1), tokenAmount);
    }

    function testPurchaseLimits() public {
        uint256 maxTokens = tokenSale.maxPurchase();
        uint256 ethCost = tokenSale.calculateEthCost(maxTokens);

        vm.prank(user1);
        tokenSale.purchaseExactTokens{value: ethCost}(maxTokens);

        // Should not be able to purchase more
        vm.prank(user1);
        vm.expectRevert("CNSTokenSale: exceeds user limit");
        tokenSale.purchaseTokens{value: 1 ether}();
    }

    function testMinPurchase() public {
        uint256 minTokens = tokenSale.minPurchase();
        uint256 ethCost = tokenSale.calculateEthCost(minTokens);

        vm.prank(user1);
        tokenSale.purchaseExactTokens{value: ethCost}(minTokens);

        assertEq(tokenL2.balanceOf(user1), minTokens);
    }

    function testCannotPurchaseBelowMin() public {
        uint256 belowMin = tokenSale.minPurchase() - 1;

        vm.prank(user1);
        vm.expectRevert("CNSTokenSale: below minimum purchase");
        tokenSale.purchaseTokens{value: 1 ether}();
    }

    function testPauseUnpause() public {
        vm.prank(owner);
        tokenSale.pause();

        vm.prank(user1);
        vm.expectRevert("Pausable: paused");
        tokenSale.purchaseTokens{value: 1 ether}();

        vm.prank(owner);
        tokenSale.unpause();

        vm.prank(user1);
        tokenSale.purchaseTokens{value: 1 ether}(); // Should work now
    }

    function testSetTokenPrice() public {
        uint256 newPrice = 0.002 ether;

        vm.prank(owner);
        tokenSale.setTokenPrice(newPrice);

        assertEq(tokenSale.tokenPrice(), newPrice);
    }

    function testSetPurchaseLimits() public {
        uint256 newMin = 200 * 10**18;
        uint256 newMax = 20000 * 10**18;

        vm.prank(owner);
        tokenSale.setPurchaseLimits(newMin, newMax);

        assertEq(tokenSale.minPurchase(), newMin);
        assertEq(tokenSale.maxPurchase(), newMax);
    }

    function testWithdrawTokens() public {
        uint256 balance = tokenL2.balanceOf(address(tokenSale));

        vm.prank(owner);
        tokenSale.withdrawTokens(address(tokenL2), balance);

        assertEq(tokenL2.balanceOf(address(tokenSale)), 0);
        assertEq(tokenL2.balanceOf(owner), balance);
    }

    function testWithdrawETH() public {
        vm.prank(user1);
        tokenSale.purchaseTokens{value: 1 ether}();

        uint256 balance = address(tokenSale).balance;

        vm.prank(owner);
        tokenSale.withdrawETH(balance);

        assertEq(address(tokenSale).balance, 0);
    }

    function testGetSaleStatus() public {
        (uint256 remaining, uint256 sold, uint256 total, bool active, bool paused) = tokenSale.getSaleStatus();

        assertEq(remaining, tokenSale.totalTokensForSale() - tokenSale.tokensSold());
        assertEq(sold, tokenSale.tokensSold());
        assertEq(total, tokenSale.totalTokensForSale());
        assertEq(active, !tokenSale.paused());
        assertEq(paused, tokenSale.paused());
    }

    function testGetUserStatus() public {
        vm.prank(user1);
        tokenSale.purchaseTokens{value: 1 ether}();

        (
            bool hasAccess,
            uint256 purchased,
            uint256 purchaseCount,
            uint256 remainingAllowance,
            bool whitelisted
        ) = tokenSale.getUserStatus(user1);

        assertEq(hasAccess, true); // Whitelisted
        assertEq(purchased, tokenSale.userPurchases(user1));
        assertEq(purchaseCount, 1);
        assertEq(remainingAllowance, tokenSale.maxPurchase() - purchased);
        assertEq(whitelisted, true);
    }

    function testEmergencyWithdraw() public {
        vm.prank(user1);
        tokenSale.purchaseTokens{value: 1 ether}();

        uint256 ethBalance = address(tokenSale).balance;
        uint256 tokenBalance = tokenL2.balanceOf(address(tokenSale));

        vm.prank(owner);
        tokenSale.emergencyWithdraw(address(0)); // Withdraw ETH

        vm.prank(owner);
        tokenSale.emergencyWithdraw(address(tokenL2)); // Withdraw tokens

        assertEq(address(tokenSale).balance, 0);
        assertEq(tokenL2.balanceOf(address(tokenSale)), 0);
    }
}

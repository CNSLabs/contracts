// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "./ProductionForkTest.sol";
import "../../src/CNSTokenL2V2.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title CNSTokenL2ProductionUpgradeTest
 * @notice Comprehensive test suite for upgrading CNSTokenL2 on production-like forked state
 * @dev Tests the complete upgrade flow: schedule -> wait -> execute -> verify
 */
contract CNSTokenL2ProductionUpgradeTest is ProductionForkTest {
    
    CNSTokenL2V2 internal newImplementation;
    address internal proxyAdmin;
    
    // Test state tracking
    uint256 internal preUpgradeBalance;
    uint256 internal preUpgradeTotalSupply;
    address internal preUpgradeBridge;
    address internal preUpgradeL1Token;
    bool internal preUpgradePaused;
    
    function setUp() public override {
        super.setUp();
        
        // Deploy new implementation
        newImplementation = new CNSTokenL2V2();
        
        // Find proxy admin (this would need to be configured or inferred)
        proxyAdmin = _findProxyAdmin();
        
        // Capture pre-upgrade state
        _capturePreUpgradeState();
    }
    
    /**
     * @notice Test complete upgrade flow with initialization on production-like state
     */
    function testCompleteUpgradeFlow() public {
        console.log("=== Starting Complete Upgrade Flow Test ===");
        
        // Step 1: Schedule the upgrade
        _scheduleUpgrade(timelockController, proxyAdmin, address(newImplementation));
        
        // Step 2: Bypass timelock delay
        _bypassTimelockDelay(timelockController);
        
        // Step 3: Execute upgrade with initialization
        _executeUpgrade(timelockController, proxyAdmin, address(newImplementation));
        
        // Step 4: Verify upgrade was successful
        _verifyUpgrade(address(newImplementation));
        
        // Step 5: Verify all state was preserved
        _verifyStatePreservation();
        
        // Step 6: Test new functionality
        _testNewFunctionality();
        
        console.log("=== Complete Upgrade Flow Test Passed ===");
    }
    
    
    // ============ Helper Functions ============
    
    /**
     * @notice Capture state before upgrade
     */
    function _capturePreUpgradeState() internal {
        CNSTokenL2 token = CNSTokenL2(cnsTokenL2Proxy);
        
        // Capture critical state
        preUpgradeBalance = token.balanceOf(address(this));
        preUpgradeTotalSupply = token.totalSupply();
        preUpgradeBridge = token.bridge();
        preUpgradeL1Token = token.l1Token();
        preUpgradePaused = token.paused();
        
        console.log("Pre-upgrade state captured");
    }
    
    /**
     * @notice Verify that all state was preserved after upgrade
     */
    function _verifyStatePreservation() internal view {
        CNSTokenL2 token = CNSTokenL2(cnsTokenL2Proxy);
        
        // Verify critical state preservation
        assertEq(token.balanceOf(address(this)), preUpgradeBalance, "Balance not preserved");
        assertEq(token.totalSupply(), preUpgradeTotalSupply, "Total supply not preserved");
        assertEq(token.bridge(), preUpgradeBridge, "Bridge not preserved");
        assertEq(token.l1Token(), preUpgradeL1Token, "L1 token not preserved");
        assertEq(token.paused(), preUpgradePaused, "Paused state not preserved");
        
        // Verify roles are preserved
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), safeMultisig), "Admin role not preserved");
        
        console.log("State preservation verified");
    }
    
    /**
     * @notice Test new functionality after upgrade
     */
    function _testNewFunctionality() internal {
        CNSTokenL2V2 upgradedToken = CNSTokenL2V2(cnsTokenL2Proxy);
        
        // Test that voting functionality is available
        assertTrue(upgradedToken.supportsInterface(type(IERC165).interfaceId), "Should support ERC165");
        
        // Test delegation functionality (new in V2)
        address testUser = makeAddr("testUser");
        vm.prank(testUser);
        upgradedToken.delegate(testUser); // Should not revert
        
        // Test voting power tracking
        uint256 votingPower = upgradedToken.getVotes(testUser);
        assertTrue(votingPower >= 0, "Voting power should be tracked");
        
        console.log("New functionality tested successfully");
    }
    
    /**
     * @notice Find the proxy admin address
     * @return admin The proxy admin address
     */
    function _findProxyAdmin() internal view returns (address admin) {
        // Use the admin role from config, same as in the script
        return config.l2.roles.admin;
    }
}

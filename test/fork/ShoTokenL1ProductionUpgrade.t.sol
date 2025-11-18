// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "./ProductionForkTest.sol";
import "../../src/ShoTokenL1V2.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title ShoTokenL1ProductionUpgradeTest
 * @notice Comprehensive test suite for upgrading ShoTokenL1 on production-like forked state
 * @dev Tests the complete upgrade flow: schedule -> wait -> execute -> verify
 */
contract ShoTokenL1ProductionUpgradeTest is ProductionForkTest {
    ShoTokenL1V2 internal newImplementation;
    address internal proxyAdmin;

    // Test state tracking
    uint256 internal preUpgradeBalance;
    uint256 internal preUpgradeTotalSupply;
    bool internal preUpgradePaused;

    function setUp() public override {
        super.setUp();

        // Deploy new implementation (V2)
        newImplementation = new ShoTokenL1V2();

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
        ShoTokenL1 token = ShoTokenL1(shoTokenL1Proxy);

        // Capture critical state
        preUpgradeBalance = token.balanceOf(address(this));
        preUpgradeTotalSupply = token.totalSupply();
        preUpgradePaused = token.paused();

        console.log("Pre-upgrade state captured");
    }

    /**
     * @notice Verify that all state was preserved after upgrade
     */
    function _verifyStatePreservation() internal view {
        ShoTokenL1 token = ShoTokenL1(shoTokenL1Proxy);

        // Verify critical state preservation
        assertEq(token.balanceOf(address(this)), preUpgradeBalance, "Balance not preserved");
        assertEq(token.totalSupply(), preUpgradeTotalSupply, "Total supply not preserved");
        assertEq(token.paused(), preUpgradePaused, "Paused state not preserved");

        // Verify roles are preserved
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), safeMultisig), "Admin role not preserved");

        console.log("State preservation verified");
    }

    /**
     * @notice Test new functionality after upgrade
     */
    function _testNewFunctionality() internal view {
        ShoTokenL1V2 upgradedToken = ShoTokenL1V2(shoTokenL1Proxy);

        // Test that the new V2 function is available
        (string memory foo, uint256 bar, bool baz) = upgradedToken.getFooData();

        // Verify the returned values
        assertEq(foo, "foo", "Foo value should be 'foo'");
        assertEq(bar, 42, "Bar value should be 42");
        assertTrue(baz, "Baz value should be true");

        console.log("New functionality tested successfully");
        console.log("  getFooData() returned:");
        console.log("    foo:", foo);
        console.log("    bar:", bar);
        console.log("    baz:", baz);
    }

    /**
     * @notice Find the proxy admin address
     * @return admin The proxy admin address
     */
    function _findProxyAdmin() internal view returns (address admin) {
        // Use the admin role from config, same as in the script
        return config.l1.roles.admin;
    }
}

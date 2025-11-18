// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./ShoTokenL1.sol";

/// @title ShoTokenL1V2 – V2 Upgrade with Test Functionality
/// @notice Adds test view function for upgrade verification
contract ShoTokenL1V2 is ShoTokenL1 {
    /* ============================================================= */
    /* ======================== V2 INITIALIZER ================== */
    /* ============================================================= */

    /**
     * @notice Initialize V2 upgrade (can be called during upgrade)
     * @dev Uses reinitializer(2) to allow calling after initial deployment
     *      This function can be used to set up any V2-specific state if needed
     */
    function initializeV2() external reinitializer(2) {
        // No initialization needed for current V2 upgrade
        // This function exists for consistency with upgrade patterns
        // and can be extended in the future if V2 needs state initialization
    }

    /* ============================================================= */
    /* ======================== V2 VIEWS ========================== */
    /* ============================================================= */

    /**
     * @notice Test view function that returns foo data
     * @return foo A test string value
     * @return bar A test uint256 value
     * @return baz A test bool value
     */
    function getFooData() external pure returns (string memory foo, uint256 bar, bool baz) {
        return ("foo", 42, true);
    }

    /* ============================================================= */
    /* ======================== STORAGE GAP ======================= */
    /* ============================================================= */

    // Storage gap remains the same as V1 (no new storage variables added)
    // This ensures storage layout compatibility
}


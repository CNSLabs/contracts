// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import {BridgedToken} from "./BridgedToken.sol";

/**
 * @title Custom BridgedToken Contract
 * @notice Custom ERC-20 token manually deployed for the Linea TokenBridge.
 * @dev Vendored from ConsenSys Linea monorepo commit c7bc6313a6309d31ac532ce0801d1c3ad3426842.
 *      The initializeV2 helper is intentionally unused; ShoTokenL2 performs the necessary parent
 *      initialization steps directly to avoid reinitializer ordering issues in tests.
 */
contract CustomBridgedToken is BridgedToken {}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {CustomBridgedToken} from "./linea/CustomBridgedToken.sol";
import {BridgedToken} from "./linea/BridgedToken.sol";

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC20VotesUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {
    ERC20PermitUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {NoncesUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/NoncesUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title CNSTokenL2V2
 * @notice Version 2 of CNS Token on L2 (Linea) - adds governance voting capabilities
 * @dev Adds ERC20VotesUpgradeable to enable delegation and voting power tracking.
 *      Maintains all v1 functionality: bridging, pausing, and allowlist controls.
 */
/// @custom:oz-upgrades-from src/CNSTokenL2.sol:CNSTokenL2
contract CNSTokenL2V2 is
    Initializable,
    CustomBridgedToken,
    ERC20VotesUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant ALLOWLIST_ADMIN_ROLE = keccak256("ALLOWLIST_ADMIN_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    address public l1Token;
    mapping(address => bool) private _senderAllowlisted;
    bool private _senderAllowlistEnabled;

    event SenderAllowlistUpdated(address indexed account, bool allowed);
    event SenderAllowlistBatchUpdated(address[] accounts, bool allowed);
    event SenderAllowlistEnabledUpdated(bool enabled);
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the V2 contract with voting capabilities
     * @dev This is called during upgrade from V1. If upgrading from V1, use initializeV2() instead.
     *      This function is kept for potential fresh deployments of V2.
     */
    function initialize(
        address admin_,
        address bridge_,
        address l1Token_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) external initializer {
        require(admin_ != address(0), "admin=0");
        require(bridge_ != address(0), "bridge=0");
        require(l1Token_ != address(0), "l1Token=0");

        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        __ERC20_init(name_, symbol_);
        __ERC20Permit_init(name_);
        __ERC20Votes_init(); // Initialize voting functionality

        bridge = bridge_;
        _decimals = decimals_;

        l1Token = l1Token_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(PAUSER_ROLE, admin_);
        _grantRole(ALLOWLIST_ADMIN_ROLE, admin_);
        _grantRole(UPGRADER_ROLE, admin_);

        _senderAllowlistEnabled = true;
        _setSenderAllowlist(address(this), true);
        _setSenderAllowlist(bridge_, true);
        _setSenderAllowlist(admin_, true);
    }

    /**
     * @notice Initializes V2-specific features when upgrading from V1
     * @dev Call this after upgrading the implementation from CNSTokenL2 to CNSTokenL2V2
     */
    function initializeV2() external reinitializer(2) {
        __ERC20Votes_init();
    }

    /**
     * @dev Override required due to multiple inheritance (BridgedToken and ERC20VotesUpgradeable)
     */
    function decimals() public view override(BridgedToken, ERC20Upgradeable) returns (uint8) {
        return _decimals;
    }

    function isSenderAllowlisted(address account) external view returns (bool) {
        return _senderAllowlisted[account];
    }

    function senderAllowlistEnabled() external view returns (bool) {
        return _senderAllowlistEnabled;
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function setSenderAllowed(address account, bool allowed) external onlyRole(ALLOWLIST_ADMIN_ROLE) {
        _setSenderAllowlist(account, allowed);
    }

    function setSenderAllowedBatch(address[] calldata accounts, bool allowed) external onlyRole(ALLOWLIST_ADMIN_ROLE) {
        for (uint256 i; i < accounts.length; ++i) {
            _setSenderAllowlist(accounts[i], allowed);
        }
        emit SenderAllowlistBatchUpdated(accounts, allowed);
    }

    function setSenderAllowlistEnabled(bool enabled) external onlyRole(ALLOWLIST_ADMIN_ROLE) {
        _senderAllowlistEnabled = enabled;
        emit SenderAllowlistEnabledUpdated(enabled);
    }

    /**
     * @dev Override required for ERC20VotesUpgradeable to track voting power on transfers
     *      Also enforces pause and sender allowlist restrictions from V1
     */
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
        whenNotPaused
    {
        // Enforce sender allowlist only if enabled (skip for mint/burn operations)
        if (_senderAllowlistEnabled && from != address(0) && to != address(0)) {
            if (!_senderAllowlisted[from]) revert("sender not allowlisted");
        }

        // Call ERC20VotesUpgradeable's _update which handles vote tracking
        super._update(from, to, value);
    }

    /**
     * @dev Override required due to multiple inheritance
     */
    function nonces(address owner) public view override(ERC20PermitUpgradeable, NoncesUpgradeable) returns (uint256) {
        return super.nonces(owner);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    function _setSenderAllowlist(address account, bool allowed) internal {
        _senderAllowlisted[account] = allowed;
        emit SenderAllowlistUpdated(account, allowed);
    }

    uint256[46] private __gap;
}

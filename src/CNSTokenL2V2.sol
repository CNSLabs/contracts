// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

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
    uint256 public constant MAX_BATCH_SIZE = 200;

    address public l1Token;
    mapping(address => bool) private _senderAllowlisted;
    bool private _senderAllowlistEnabled;

    event SenderAllowlistUpdated(address indexed account, bool allowed);
    event SenderAllowlistBatchUpdated(address[] accounts, bool allowed);
    event SenderAllowlistEnabledUpdated(bool enabled);
    event Initialized(
        address indexed admin,
        address indexed bridge,
        address indexed l1Token,
        string name,
        string symbol,
        uint8 decimals
    );

    function version() public pure virtual returns (string memory) {
        return "2.0.0";
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the V2 contract with voting capabilities
     * @dev This is for fresh deployments of V2. If upgrading from V1, use initializeV2() instead.
     */
    /// @notice Initialize the token with role separation
    /// @param defaultAdmin_ Address for DEFAULT_ADMIN_ROLE (governance address)
    /// @param upgrader_ Address for UPGRADER_ROLE (can upgrade the contract)
    /// @param pauser_ Address for PAUSER_ROLE (can pause/unpause in emergencies)
    /// @param allowlistAdmin_ Address for ALLOWLIST_ADMIN_ROLE (manages transfer allowlist)
    /// @param bridge_ Linea bridge contract address
    /// @param l1Token_ L1 token address
    /// @param name_ Token name
    /// @param symbol_ Token symbol
    /// @param decimals_ Token decimals
    function initialize(
        address defaultAdmin_,
        address upgrader_,
        address pauser_,
        address allowlistAdmin_,
        address bridge_,
        address l1Token_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) external initializer {
        require(defaultAdmin_ != address(0), "defaultAdmin=0");
        require(upgrader_ != address(0), "upgrader=0");
        require(pauser_ != address(0), "pauser=0");
        require(allowlistAdmin_ != address(0), "allowlistAdmin=0");
        require(bridge_ != address(0), "bridge=0");
        require(bridge_.code.length > 0, "bridge must be contract");
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

        // Grant critical roles
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin_);
        _grantRole(UPGRADER_ROLE, upgrader_);

        // Grant operational roles to dedicated addresses
        _grantRole(PAUSER_ROLE, pauser_);
        _grantRole(ALLOWLIST_ADMIN_ROLE, allowlistAdmin_);

        // Grant defaultAdmin as backup for operational roles
        _grantRole(PAUSER_ROLE, defaultAdmin_);
        _grantRole(ALLOWLIST_ADMIN_ROLE, defaultAdmin_);

        _senderAllowlistEnabled = true;
        _setSenderAllowlist(address(this), true);
        _setSenderAllowlist(bridge_, true);
        _setSenderAllowlist(defaultAdmin_, true);

        emit Initialized(defaultAdmin_, bridge_, l1Token_, name_, symbol_, decimals_);
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
        require(account != address(0), "zero address");
        _setSenderAllowlist(account, allowed);
    }

    function setSenderAllowedBatch(address[] calldata accounts, bool allowed) external onlyRole(ALLOWLIST_ADMIN_ROLE) {
        require(accounts.length > 0, "empty batch");
        require(accounts.length <= MAX_BATCH_SIZE, "batch too large");

        for (uint256 i; i < accounts.length; ++i) {
            require(accounts[i] != address(0), "zero address");
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

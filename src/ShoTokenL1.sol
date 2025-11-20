// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {
    ERC20PermitUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

/// @title ShoTokenL1 – Canonical L1 Token with Allowlist-Controlled Transfers
/// @notice Only allowlisted addresses can transfer.
contract ShoTokenL1 is
    Initializable,
    ERC20PermitUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    // ────────────────────────────────────────────────────────────── Roles
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant ALLOWLIST_ADMIN_ROLE = keccak256("ALLOWLIST_ADMIN_ROLE");

    // ─────────────────────────────────────────────────────── Constants
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 ether; // 1 B tokens
    uint256 public constant MAX_BATCH_SIZE = 200;

    // ─────────────────────────────────────────────────────── State
    mapping(address => bool) private _senderAllowlisted;
    bool private _senderAllowlistEnabled;

    // ─────────────────────────────────────────────────────── Errors
    error InvalidDefaultAdmin();
    error InvalidUpgrader();
    error InvalidPauser();
    error InvalidAllowlistAdmin();
    error SenderNotAllowlisted();
    error ZeroAddress();
    error EmptyBatch();
    error BatchTooLarge();

    // ─────────────────────────────────────────────────────── Events
    event SenderAllowlistUpdated(address indexed account, bool allowed);
    event SenderAllowlistBatchUpdated(address[] accounts, bool allowed);
    event SenderAllowlistEnabledUpdated(bool enabled);
    event Initialized(address indexed admin, address indexed initialRecipient, string name, string symbol);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /* ============================================================= */
    /* ========================= INITIALIZER ======================= */
    /* ============================================================= */

    /**
     * @notice Initialize token with full supply and allowlist enabled
     * @param defaultAdmin_      DEFAULT_ADMIN_ROLE
     * @param upgrader_          UPGRADER_ROLE
     * @param pauser_            PAUSER_ROLE
     * @param allowlistAdmin_    ALLOWLIST_ADMIN_ROLE
     * @param initialRecipient   Receives full 1B supply
     * @param name_              Token name
     * @param symbol_            Token symbol
     * @param initialAllowlist_  Optional pre-allowlist addresses
     */
    function initialize(
        address defaultAdmin_,
        address upgrader_,
        address pauser_,
        address allowlistAdmin_,
        address initialRecipient,
        string memory name_,
        string memory symbol_,
        address[] calldata initialAllowlist_
    ) external initializer {
        if (defaultAdmin_ == address(0)) revert InvalidDefaultAdmin();
        if (upgrader_ == address(0)) revert InvalidUpgrader();
        if (pauser_ == address(0)) revert InvalidPauser();
        if (allowlistAdmin_ == address(0)) revert InvalidAllowlistAdmin();
        if (initialRecipient == address(0)) revert ZeroAddress();

        __ERC20_init(name_, symbol_);
        __ERC20Permit_init(name_);
        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin_);
        _grantRole(UPGRADER_ROLE, upgrader_);
        _grantRole(PAUSER_ROLE, pauser_);
        _grantRole(ALLOWLIST_ADMIN_ROLE, allowlistAdmin_);

        // Backup roles for admin
        _grantRole(PAUSER_ROLE, defaultAdmin_);
        _grantRole(ALLOWLIST_ADMIN_ROLE, defaultAdmin_);

        // Mint full supply
        _mint(initialRecipient, INITIAL_SUPPLY);

        // Enable allowlist
        _senderAllowlistEnabled = true;

        // Default allowlisted actors
        _setSenderAllowlist(address(this), true); // contract itself
        _setSenderAllowlist(defaultAdmin_, true); // admin

        // Optional: pre-allowlist others
        if (initialAllowlist_.length > 0) {
            _setBatchSenderAllowlist(initialAllowlist_, true);
        }

        emit Initialized(defaultAdmin_, initialRecipient, name_, symbol_);
    }

    /* ============================================================= */
    /* =========================== VIEWS =========================== */
    /* ============================================================= */

    function isSenderAllowlisted(address account) external view returns (bool) {
        return _senderAllowlisted[account];
    }

    function senderAllowlistEnabled() external view returns (bool) {
        return _senderAllowlistEnabled;
    }

    /* ============================================================= */
    /* =========================== PAUSE =========================== */
    /* ============================================================= */

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /* ============================================================= */
    /* ====================== ALLOWLIST ADMIN ===================== */
    /* ============================================================= */

    function setSenderAllowed(address account, bool allowed) external onlyRole(ALLOWLIST_ADMIN_ROLE) {
        if (account == address(0)) revert ZeroAddress();
        _setSenderAllowlist(account, allowed);
    }

    function setSenderAllowedBatch(address[] calldata accounts, bool allowed) external onlyRole(ALLOWLIST_ADMIN_ROLE) {
        _setBatchSenderAllowlist(accounts, allowed);
    }

    function setSenderAllowlistEnabled(bool enabled) external onlyRole(ALLOWLIST_ADMIN_ROLE) {
        _senderAllowlistEnabled = enabled;
        emit SenderAllowlistEnabledUpdated(enabled);
    }

    /* ============================================================= */
    /* ======================= TRANSFER HOOK ====================== */
    /* ============================================================= */

    /// @dev Only allowlisted senders can transfer (to anyone)
    function _update(address from, address to, uint256 value) internal override whenNotPaused {
        if (_senderAllowlistEnabled && from != address(0) && to != address(0)) {
            if (!_senderAllowlisted[from]) {
                revert SenderNotAllowlisted();
            }
        }
        super._update(from, to, value);
    }

    /* ============================================================= */
    /* ======================== UPGRADE AUTH ====================== */
    /* ============================================================= */

    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}

    /* ============================================================= */
    /* ====================== INTERNAL HELPERS ==================== */
    /* ============================================================= */

    function _setSenderAllowlist(address account, bool allowed) private {
        _senderAllowlisted[account] = allowed;
        emit SenderAllowlistUpdated(account, allowed);
    }

    function _setBatchSenderAllowlist(address[] calldata accounts, bool allowed) private {
        if (accounts.length == 0) revert EmptyBatch();
        if (accounts.length > MAX_BATCH_SIZE) revert BatchTooLarge();

        for (uint256 i; i < accounts.length; ++i) {
            if (accounts[i] == address(0)) revert ZeroAddress();
            _setSenderAllowlist(accounts[i], allowed);
        }
        emit SenderAllowlistBatchUpdated(accounts, allowed);
    }

    /* ============================================================= */
    /* ======================== STORAGE GAP ======================= */
    /* ============================================================= */

    uint256[50] private __gap;
}

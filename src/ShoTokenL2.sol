// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {CustomBridgedToken} from "./linea/CustomBridgedToken.sol";

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract ShoTokenL2 is
    Initializable,
    CustomBridgedToken,
    PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    // Custom errors for gas optimization
    error InvalidDefaultAdmin();
    error InvalidUpgrader();
    error InvalidPauser();
    error InvalidAllowlistAdmin();
    error InvalidBridge();
    error InvalidL1Token();
    error SenderNotAllowlisted();
    error ZeroAddress();
    error EmptyBatch();
    error BatchTooLarge();
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
        return "1.0.0";
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

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
    /// @param senderAllowlist_ Array of addresses to add to sender allowlist during initialization
    function initialize(
        address defaultAdmin_,
        address upgrader_,
        address pauser_,
        address allowlistAdmin_,
        address bridge_,
        address l1Token_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address[] calldata senderAllowlist_
    ) external initializer {
        if (defaultAdmin_ == address(0)) revert InvalidDefaultAdmin();
        if (upgrader_ == address(0)) revert InvalidUpgrader();
        if (pauser_ == address(0)) revert InvalidPauser();
        if (allowlistAdmin_ == address(0)) revert InvalidAllowlistAdmin();
        if (bridge_ == address(0)) revert InvalidBridge();
        if (l1Token_ == address(0)) revert InvalidL1Token();

        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        __ERC20_init(name_, symbol_);
        __ERC20Permit_init(name_);
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

        // Add additional senderAllowlist addresses provided during initialization
        if (senderAllowlist_.length > 0) {
            _setBatchSenderAllowlist(senderAllowlist_, true);
        }

        emit Initialized(defaultAdmin_, bridge_, l1Token_, name_, symbol_, decimals_);
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
        if (account == address(0)) revert ZeroAddress();
        _setSenderAllowlist(account, allowed);
    }

    function setSenderAllowedBatch(address[] calldata accounts, bool allowed) external onlyRole(ALLOWLIST_ADMIN_ROLE) {
        _setBatchSenderAllowlist(accounts, allowed);
        emit SenderAllowlistBatchUpdated(accounts, allowed);
    }

    function setSenderAllowlistEnabled(bool enabled) external onlyRole(ALLOWLIST_ADMIN_ROLE) {
        _senderAllowlistEnabled = enabled;
        emit SenderAllowlistEnabledUpdated(enabled);
    }

    /**
     * @dev Override _update to enforce sender allowlist restrictions
     * @notice Bridge operations (mint/burn) bypass allowlist checks by design
     * @dev Minting (from=0) and burning (to=0) are allowed for bridge operations
     * @dev Transfers (from!=0 && to!=0) require sender to be allowlisted
     * @dev This design ensures:
     *      - Bridge can mint tokens to any address (required for L1→L2 bridging)
     *      - Bridge can burn tokens from any address (required for L2→L1 bridging)
     *      - Users must be allowlisted to transfer tokens (restrictive by design)
     * @dev Recipients of bridged tokens must be allowlisted by admin to transfer
     */
    function _update(address from, address to, uint256 value) internal override(ERC20Upgradeable) whenNotPaused {
        // Enforce sender allowlist only for transfers (not mint/burn operations)
        if (_senderAllowlistEnabled && from != address(0) && to != address(0)) {
            if (!_senderAllowlisted[from]) revert SenderNotAllowlisted();
        }
        super._update(from, to, value);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    function _setSenderAllowlist(address account, bool allowed) internal {
        _senderAllowlisted[account] = allowed;
        emit SenderAllowlistUpdated(account, allowed);
    }

    /// @notice Internal batch setter for sender allowlist with validation
    /// @param accounts Array of addresses to update
    /// @param allowed True to allowlist, false to remove from allowlist
    function _setBatchSenderAllowlist(address[] calldata accounts, bool allowed) internal {
        if (accounts.length == 0) revert EmptyBatch();
        if (accounts.length > MAX_BATCH_SIZE) revert BatchTooLarge();

        for (uint256 i; i < accounts.length; ++i) {
            if (accounts[i] == address(0)) revert ZeroAddress();
            _setSenderAllowlist(accounts[i], allowed);
        }
    }

    uint256[46] private __gap;
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {CustomBridgedToken} from "./linea/CustomBridgedToken.sol";

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract CNSTokenL2 is
    Initializable,
    CustomBridgedToken,
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
    event BridgeSet(address indexed bridge);
    event L1TokenSet(address indexed l1Token);
    event Initialized(
        address indexed admin,
        address indexed bridge,
        address indexed l1Token,
        string name,
        string symbol,
        uint8 decimals
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

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
        require(bridge_.code.length > 0, "bridge must be contract");
        require(l1Token_ != address(0), "l1Token=0");

        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        __ERC20_init(name_, symbol_);
        __ERC20Permit_init(name_);
        bridge = bridge_;
        emit BridgeSet(bridge_);

        _decimals = decimals_;

        l1Token = l1Token_;
        emit L1TokenSet(l1Token_);

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(PAUSER_ROLE, admin_);
        _grantRole(ALLOWLIST_ADMIN_ROLE, admin_);
        _grantRole(UPGRADER_ROLE, admin_);

        _senderAllowlistEnabled = true;
        _setSenderAllowlist(address(this), true);
        _setSenderAllowlist(bridge_, true);
        _setSenderAllowlist(admin_, true);

        emit Initialized(admin_, bridge_, l1Token_, name_, symbol_, decimals_);
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

    function _update(address from, address to, uint256 value) internal override(ERC20Upgradeable) whenNotPaused {
        // Enforce sender allowlist only if enabled
        if (_senderAllowlistEnabled && from != address(0) && to != address(0)) {
            if (!_senderAllowlisted[from]) revert("sender not allowlisted");
        }
        super._update(from, to, value);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    function _setSenderAllowlist(address account, bool allowed) internal {
        _senderAllowlisted[account] = allowed;
        emit SenderAllowlistUpdated(account, allowed);
    }

    uint256[46] private __gap;
}

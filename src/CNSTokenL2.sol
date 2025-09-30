// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

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

    address public l1Token;
    mapping(address => bool) private _allowlisted;

    event AllowlistUpdated(address indexed account, bool allowed);
    event AllowlistBatchUpdated(address[] accounts, bool allowed);

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
        require(l1Token_ != address(0), "l1Token=0");

        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        __ERC20_init(name_, symbol_);
        __ERC20Permit_init(name_);
        bridge = bridge_;
        _decimals = decimals_;

        l1Token = l1Token_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(PAUSER_ROLE, admin_);
        _grantRole(ALLOWLIST_ADMIN_ROLE, admin_);
        _grantRole(UPGRADER_ROLE, admin_);

        _setAllowlist(address(this), true);
        _setAllowlist(bridge_, true);
        _setAllowlist(admin_, true);
    }

    function isAllowlisted(address account) external view returns (bool) {
        return _allowlisted[account];
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function setAllowlist(address account, bool allowed) external onlyRole(ALLOWLIST_ADMIN_ROLE) {
        _setAllowlist(account, allowed);
    }

    function setAllowlistBatch(address[] calldata accounts, bool allowed) external onlyRole(ALLOWLIST_ADMIN_ROLE) {
        for (uint256 i; i < accounts.length; ++i) {
            _setAllowlist(accounts[i], allowed);
        }
        emit AllowlistBatchUpdated(accounts, allowed);
    }

    function _update(address from, address to, uint256 value) internal override(ERC20Upgradeable) whenNotPaused {
        if (from != address(0) && to != address(0)) {
            if (!_allowlisted[from]) revert("from not allowlisted");
            if (!_allowlisted[to]) revert("to not allowlisted");
        }
        super._update(from, to, value);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    function _setAllowlist(address account, bool allowed) internal {
        _allowlisted[account] = allowed;
        emit AllowlistUpdated(account, allowed);
    }

    uint256[47] private __gap;
}

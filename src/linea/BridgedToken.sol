// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import {ERC20PermitUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

/**
 * @title BridgedToken Contract
 * @notice ERC-20 token created when a native token is bridged to a target chain.
 * @custom:security-contact security-report@linea.build
 * @dev Vendored from ConsenSys Linea monorepo commit c7bc6313a6309d31ac532ce0801d1c3ad3426842.
 */
contract BridgedToken is ERC20PermitUpgradeable {
    address public bridge;
    uint8 public _decimals;

    /// @dev Keep free storage slots for future implementation updates to avoid storage collision.
    uint256[50] private __gap;

    error OnlyBridge(address bridgeAddress);

    /// @dev Disable constructor for safety
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(string memory _tokenName, string memory _tokenSymbol, uint8 _tokenDecimals)
        external
        initializer
    {
        __ERC20_init(_tokenName, _tokenSymbol);
        __ERC20Permit_init(_tokenName);
        bridge = msg.sender;
        _decimals = _tokenDecimals;
    }

    /// @dev Ensures call come from the bridge.
    modifier onlyBridge() {
        if (msg.sender != bridge) revert OnlyBridge(bridge);
        _;
    }

    /**
     * @dev Called by the bridge to mint tokens during a bridge transaction.
     * @param _recipient The address to receive the minted tokens.
     * @param _amount The amount of tokens to mint.
     */
    function mint(address _recipient, uint256 _amount) external onlyBridge {
        _mint(_recipient, _amount);
    }

    /**
     * @dev Called by the bridge to burn tokens during a bridge transaction.
     * @dev User should first have allowed the bridge to spend tokens on their behalf.
     * @param _account The account from which tokens will be burned.
     * @param _amount The amount of tokens to burn.
     */
    function burn(address _account, uint256 _amount) external onlyBridge {
        _spendAllowance(_account, msg.sender, _amount);
        _burn(_account, _amount);
    }

    /**
     * @dev Overrides ERC-20 default function to support tokens with different decimals.
     * @return The number of decimal.
     * @custom:modification Added 'virtual' modifier to allow further overriding in derived contracts (specifically to be able upgrade to use ERC20VotesUpgradeable)
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}

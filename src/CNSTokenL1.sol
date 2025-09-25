// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title CNSTokenL1
 * @dev CNS Token on L1 - the canonical home for the token
 * Includes bridge functionality and administrative controls
 */
contract CNSTokenL1 is ERC20, ERC20Burnable, ERC20Pausable, Ownable, ERC20Permit {
    // Bridge contract address on L1
    address public l1Bridge;

    // Authorized minter for bridge operations
    address public minter;

    // Total supply cap
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10 ** 18; // 1 billion tokens

    // Events
    event BridgeContractSet(address indexed bridge);
    event MinterSet(address indexed minter);
    event TokensMinted(address indexed to, uint256 amount);

    /**
     * @dev Constructor
     * @param initialOwner The owner of the contract
     */
    constructor(address initialOwner) ERC20("CNS Token", "CNS") Ownable(initialOwner) ERC20Permit("CNS Token") {
        _mint(initialOwner, 100_000_000 * 10 ** 18); // Mint 100M tokens to owner
    }

    /**
     * @dev Modifier to check if caller is bridge or owner
     */
    modifier onlyBridgeOrOwner() {
        require(msg.sender == l1Bridge || msg.sender == owner(), "CNSTokenL1: caller is not bridge or owner");
        _;
    }

    /**
     * @dev Set the L1 bridge contract address
     * @param _bridge Address of the L1 bridge contract
     */
    function setBridgeContract(address _bridge) external onlyOwner {
        require(_bridge != address(0), "CNSTokenL1: invalid bridge address");
        l1Bridge = _bridge;
        emit BridgeContractSet(_bridge);
    }

    /**
     * @dev Set the authorized minter
     * @param _minter Address authorized to mint tokens
     */
    function setMinter(address _minter) external onlyOwner {
        require(_minter != address(0), "CNSTokenL1: invalid minter address");
        minter = _minter;
        emit MinterSet(_minter);
    }

    /**
     * @dev Mint tokens (only bridge or owner can call)
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyBridgeOrOwner {
        require(to != address(0), "CNSTokenL1: cannot mint to zero address");
        require(totalSupply() + amount <= MAX_SUPPLY, "CNSTokenL1: max supply exceeded");

        _mint(to, amount);
        emit TokensMinted(to, amount);
    }

    /**
     * @dev Burn tokens (only bridge can call)
     * @param amount Amount of tokens to burn
     */
    function burn(uint256 amount) public override onlyBridgeOrOwner {
        super.burn(amount);
    }

    /**
     * @dev Burn tokens from specific address (only bridge can call)
     * @param account Address to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function burnFrom(address account, uint256 amount) public override onlyBridgeOrOwner {
        super.burnFrom(account, amount);
    }

    /**
     * @dev Pause token transfers
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause token transfers
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Hook that is called before any transfer of tokens
     */
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Pausable) {
        super._update(from, to, value);
    }
}

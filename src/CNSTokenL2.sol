// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title CNSTokenL2
 * @dev CNS Token on L2 - bridged version with potential modifications
 * This contract handles the L2 representation of the L1 token
 */
contract CNSTokenL2 is ERC20, ERC20Burnable, ERC20Pausable, Ownable, ERC20Permit {
    // L1 token contract address
    address public l1Token;

    // L2 bridge contract address
    address public l2Bridge;

    // Authorized minter for bridge operations
    address public minter;

    // Mapping to track locked tokens for bridging
    mapping(address => uint256) public lockedTokens;

    // Total supply cap (may differ from L1)
    uint256 public constant L2_MAX_SUPPLY = 2_000_000_000 * 10 ** 18; // 2 billion tokens on L2

    // Events
    event L1TokenSet(address indexed l1Token);
    event L2BridgeSet(address indexed bridge);
    event MinterSet(address indexed minter);
    event TokensMinted(address indexed to, uint256 amount);
    event TokensLocked(address indexed from, uint256 amount);
    event TokensUnlocked(address indexed to, uint256 amount);

    /**
     * @dev Constructor
     * @param initialOwner The owner of the contract
     * @param _l1Token Address of the L1 token contract
     */
    constructor(address initialOwner, address _l1Token)
        ERC20("CNS Token L2", "CNS-L2")
        Ownable(initialOwner)
        ERC20Permit("CNS Token L2")
    {
        require(_l1Token != address(0), "CNSTokenL2: invalid L1 token address");
        l1Token = _l1Token;
    }

    /**
     * @dev Modifier to check if caller is bridge or owner
     */
    modifier onlyBridgeOrOwner() {
        require(msg.sender == l2Bridge || msg.sender == owner(), "CNSTokenL2: caller is not bridge or owner");
        _;
    }

    /**
     * @dev Set the L1 token contract address
     * @param _l1Token Address of the L1 token contract
     */
    function setL1Token(address _l1Token) external onlyOwner {
        require(_l1Token != address(0), "CNSTokenL2: invalid L1 token address");
        l1Token = _l1Token;
        emit L1TokenSet(_l1Token);
    }

    /**
     * @dev Set the L2 bridge contract address
     * @param _bridge Address of the L2 bridge contract
     */
    function setBridgeContract(address _bridge) external onlyOwner {
        require(_bridge != address(0), "CNSTokenL2: invalid bridge address");
        l2Bridge = _bridge;
        emit L2BridgeSet(_bridge);
    }

    /**
     * @dev Set the authorized minter
     * @param _minter Address authorized to mint tokens
     */
    function setMinter(address _minter) external onlyOwner {
        require(_minter != address(0), "CNSTokenL2: invalid minter address");
        minter = _minter;
        emit MinterSet(_minter);
    }

    /**
     * @dev Mint tokens (only bridge or owner can call)
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "CNSTokenL2: cannot mint to zero address");
        require(totalSupply() + amount <= L2_MAX_SUPPLY, "CNSTokenL2: max supply exceeded");

        _mint(to, amount);
        emit TokensMinted(to, amount);
    }

    /**
     * @dev Burn tokens (only bridge can call)
     * @param amount Amount of tokens to burn
     */
    function burn(uint256 amount) public override onlyOwner {
        super.burn(amount);
    }

    /**
     * @dev Burn tokens from specific address (only bridge can call)
     * @param account Address to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function burnFrom(address account, uint256 amount) public override onlyOwner {
        super.burnFrom(account, amount);
    }

    /**
     * @dev Lock tokens for bridging to L1
     * @param amount Amount of tokens to lock
     */
    function lockTokens(uint256 amount) external {
        require(amount > 0, "CNSTokenL2: amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "CNSTokenL2: insufficient balance");

        _transfer(msg.sender, address(this), amount);
        lockedTokens[msg.sender] += amount;

        emit TokensLocked(msg.sender, amount);
    }

    /**
     * @dev Unlock tokens (called by bridge after successful L1 transfer)
     * @param to Address to unlock tokens to
     * @param amount Amount of tokens to unlock
     */
    function unlockTokens(address to, uint256 amount) external onlyOwner {
        require(lockedTokens[to] >= amount, "CNSTokenL2: insufficient locked tokens");

        lockedTokens[to] -= amount;
        _transfer(address(this), to, amount);

        emit TokensUnlocked(to, amount);
    }

    /**
     * @dev Get locked token balance for an address
     * @param account Address to check
     */
    function getLockedBalance(address account) external view returns (uint256) {
        return lockedTokens[account];
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

    /**
     * @dev Emergency function to transfer tokens out of contract (only owner)
     * @param token Address of token to transfer
     * @param to Address to transfer to
     * @param amount Amount to transfer
     */
    function emergencyTransfer(address token, address to, uint256 amount) external onlyOwner {
        require(to != address(0), "CNSTokenL2: cannot transfer to zero address");

        if (token == address(this)) {
            _transfer(address(this), to, amount);
        } else {
            IERC20(token).transfer(to, amount);
        }
    }
}

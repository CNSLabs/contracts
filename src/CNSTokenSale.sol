// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title CNSTokenSale
 * @dev Wrapped Uniswap V3-style token sale contract with NFT-based access control
 * Only users with appropriate NFT tiers can participate based on time progression
 */
contract CNSTokenSale is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // Token being sold
    IERC20 public saleToken;

    // Access control contracts
    address public accessNFT;
    address public tierProgression;

    // Sale parameters
    uint256 public tokenPrice; // Price per token in wei
    uint256 public minPurchase; // Minimum purchase amount
    uint256 public maxPurchase; // Maximum purchase amount per user
    uint256 public totalTokensForSale; // Total tokens allocated for sale
    uint256 public tokensSold; // Tokens sold so far

    // User purchase tracking
    mapping(address => uint256) public userPurchases;
    mapping(address => uint256) public userPurchaseCount;

    // Whitelist for early access
    mapping(address => bool) public whitelist;

    // Events
    event TokensPurchased(address indexed buyer, uint256 amount, uint256 cost);
    event TokenPriceUpdated(uint256 newPrice);
    event PurchaseLimitsUpdated(uint256 min, uint256 max);
    event TokensWithdrawn(address indexed token, uint256 amount);
    event FundsWithdrawn(address indexed token, uint256 amount);
    event AccessContractsUpdated(address indexed nft, address indexed progression);
    event UserWhitelisted(address indexed user, bool status);

    /**
     * @dev Constructor
     * @param _saleToken Address of the token being sold
     * @param _accessNFT Address of the NFT access control contract
     * @param _tierProgression Address of the tier progression contract
     * @param initialOwner The owner of the contract
     */
    constructor(address _saleToken, address _accessNFT, address _tierProgression, address initialOwner)
        Ownable(initialOwner)
    {
        require(_saleToken != address(0), "CNSTokenSale: invalid token address");
        require(_accessNFT != address(0), "CNSTokenSale: invalid NFT address");
        require(_tierProgression != address(0), "CNSTokenSale: invalid progression address");

        saleToken = IERC20(_saleToken);
        accessNFT = _accessNFT;
        tierProgression = _tierProgression;

        // Set default values
        tokenPrice = 0.001 ether; // 1 token = 0.001 ETH
        minPurchase = 100 * 10 ** 18; // 100 tokens minimum
        maxPurchase = 10000 * 10 ** 18; // 10,000 tokens maximum per user
        totalTokensForSale = 100000000 * 10 ** 18; // 100M tokens for sale
    }

    /**
     * @dev Update token price
     */
    function setTokenPrice(uint256 _tokenPrice) external onlyOwner {
        require(_tokenPrice > 0, "CNSTokenSale: price must be greater than 0");
        tokenPrice = _tokenPrice;
        emit TokenPriceUpdated(_tokenPrice);
    }

    /**
     * @dev Update purchase limits
     */
    function setPurchaseLimits(uint256 _min, uint256 _max) external onlyOwner {
        require(_min > 0, "CNSTokenSale: min must be greater than 0");
        require(_max >= _min, "CNSTokenSale: max must be >= min");

        minPurchase = _min;
        maxPurchase = _max;
        emit PurchaseLimitsUpdated(_min, _max);
    }

    /**
     * @dev Update access control contracts
     */
    function setAccessContracts(address _accessNFT, address _tierProgression) external onlyOwner {
        require(_accessNFT != address(0), "CNSTokenSale: invalid NFT address");
        require(_tierProgression != address(0), "CNSTokenSale: invalid progression address");

        accessNFT = _accessNFT;
        tierProgression = _tierProgression;
        emit AccessContractsUpdated(_accessNFT, _tierProgression);
    }

    /**
     * @dev Add/remove users from whitelist
     */
    function setWhitelist(address user, bool status) external onlyOwner {
        whitelist[user] = status;
        emit UserWhitelisted(user, status);
    }

    /**
     * @dev Batch set whitelist
     */
    function setWhitelistBatch(address[] memory users, bool status) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            whitelist[users[i]] = status;
            emit UserWhitelisted(users[i], status);
        }
    }

    /**
     * @dev Calculate token amount for given ETH amount
     */
    function calculateTokenAmount(uint256 ethAmount) public view returns (uint256) {
        return (ethAmount * 10 ** 18) / tokenPrice;
    }

    /**
     * @dev Calculate ETH cost for token amount
     */
    function calculateEthCost(uint256 tokenAmount) public view returns (uint256) {
        return (tokenAmount * tokenPrice) / 10 ** 18;
    }

    /**
     * @dev Check if user has access to purchase
     */
    function hasPurchaseAccess(address user) public view returns (bool) {
        // Whitelisted users always have access
        if (whitelist[user]) {
            return true;
        }

        // Check tier-based access through tier progression contract
        // In a real implementation, you'd call the tier progression contract
        // For now, we'll return false to force integration
        return false;
    }

    /**
     * @dev Get user's remaining purchase allowance
     */
    function getRemainingAllowance(address user) public view returns (uint256) {
        if (userPurchases[user] >= maxPurchase) {
            return 0;
        }
        return maxPurchase - userPurchases[user];
    }

    /**
     * @dev Purchase tokens
     */
    function purchaseTokens() external payable nonReentrant whenNotPaused {
        require(msg.value > 0, "CNSTokenSale: no ETH sent");
        require(hasPurchaseAccess(msg.sender), "CNSTokenSale: no purchase access");
        require(tokensSold < totalTokensForSale, "CNSTokenSale: sale completed");

        uint256 tokenAmount = calculateTokenAmount(msg.value);
        uint256 remainingAllowance = getRemainingAllowance(msg.sender);

        require(tokenAmount >= minPurchase, "CNSTokenSale: below minimum purchase");
        require(tokenAmount <= remainingAllowance, "CNSTokenSale: exceeds user limit");
        require(tokensSold + tokenAmount <= totalTokensForSale, "CNSTokenSale: exceeds total supply");

        // Update user purchase tracking
        userPurchases[msg.sender] += tokenAmount;
        userPurchaseCount[msg.sender]++;
        tokensSold += tokenAmount;

        // Transfer tokens to buyer
        saleToken.safeTransfer(msg.sender, tokenAmount);

        emit TokensPurchased(msg.sender, tokenAmount, msg.value);
    }

    /**
     * @dev Purchase specific token amount
     */
    function purchaseExactTokens(uint256 tokenAmount) external payable nonReentrant whenNotPaused {
        require(hasPurchaseAccess(msg.sender), "CNSTokenSale: no purchase access");
        require(tokenAmount >= minPurchase, "CNSTokenSale: below minimum purchase");
        require(tokenAmount <= getRemainingAllowance(msg.sender), "CNSTokenSale: exceeds user limit");
        require(tokensSold + tokenAmount <= totalTokensForSale, "CNSTokenSale: exceeds total supply");

        uint256 ethCost = calculateEthCost(tokenAmount);

        // Update user purchase tracking
        userPurchases[msg.sender] += tokenAmount;
        userPurchaseCount[msg.sender]++;
        tokensSold += tokenAmount;

        // Transfer tokens to buyer
        saleToken.safeTransfer(msg.sender, tokenAmount);

        // Transfer ETH to contract (this would normally go to Uniswap pool)
        // For now, we'll just require the exact amount
        require(msg.value == ethCost, "CNSTokenSale: incorrect ETH amount");

        emit TokensPurchased(msg.sender, tokenAmount, ethCost);
    }

    /**
     * @dev Withdraw unsold tokens (only owner)
     */
    function withdrawTokens(address token, uint256 amount) external onlyOwner {
        require(token != address(0), "CNSTokenSale: invalid token address");

        IERC20(token).safeTransfer(owner(), amount);
        emit TokensWithdrawn(token, amount);
    }

    /**
     * @dev Withdraw ETH (only owner)
     */
    function withdrawETH(uint256 amount) external onlyOwner {
        require(amount <= address(this).balance, "CNSTokenSale: insufficient balance");

        payable(owner()).transfer(amount);
        emit FundsWithdrawn(address(0), amount);
    }

    /**
     * @dev Pause the sale
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause the sale
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Get sale status
     */
    function getSaleStatus()
        external
        view
        returns (uint256 tokensRemaining, uint256 tokensSold_, uint256 totalSupply, bool isActive, bool isPaused)
    {
        return (totalTokensForSale - tokensSold, tokensSold, totalTokensForSale, !paused(), paused());
    }

    /**
     * @dev Get user status
     */
    function getUserStatus(address user)
        external
        view
        returns (
            bool hasAccess,
            uint256 purchased,
            uint256 purchaseCount,
            uint256 remainingAllowance,
            bool isWhitelisted
        )
    {
        return (
            hasPurchaseAccess(user),
            userPurchases[user],
            userPurchaseCount[user],
            getRemainingAllowance(user),
            whitelist[user]
        );
    }

    /**
     * @dev Emergency withdraw all tokens (only owner)
     */
    function emergencyWithdraw(address token) external onlyOwner {
        if (token == address(0)) {
            // Withdraw ETH
            payable(owner()).transfer(address(this).balance);
            emit FundsWithdrawn(address(0), address(this).balance);
        } else {
            // Withdraw tokens
            uint256 balance = IERC20(token).balanceOf(address(this));
            IERC20(token).safeTransfer(owner(), balance);
            emit TokensWithdrawn(token, balance);
        }
    }

    /**
     * @dev Receive function to accept ETH
     */
    receive() external payable {}
}

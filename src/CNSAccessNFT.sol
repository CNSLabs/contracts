// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title CNSAccessNFT
 * @dev NFT contract for access control with 3 priority tiers
 * Tier 1: Highest priority (Day 1 access)
 * Tier 2: Medium priority (Days 2-3 access)
 * Tier 3: Standard priority (Days 4+ access)
 */
contract CNSAccessNFT is ERC721, ERC721URIStorage, Ownable, ReentrancyGuard {
    // Tier definitions
    enum Tier {
        NONE,
        TIER1,
        TIER2,
        TIER3
    }

    // Token ID counter
    uint256 private _nextTokenId = 1;

    // Tier limits
    uint256 public constant TIER1_LIMIT = 100;
    uint256 public constant TIER2_LIMIT = 500;
    uint256 public constant TIER3_LIMIT = 1000;

    // Minting costs (in wei)
    uint256 public tier1Price = 1 ether;
    uint256 public tier2Price = 0.5 ether;
    uint256 public tier3Price = 0.1 ether;

    // Token metadata
    string private _baseTokenURI;

    // Tier mappings
    mapping(uint256 => Tier) public tokenTiers;
    mapping(Tier => uint256) public tierCounts;
    mapping(Tier => uint256) public tierMinted;

    // Sale state
    bool public saleActive = false;
    bool public tier1SoldOut = false;
    bool public tier2SoldOut = false;
    bool public tier3SoldOut = false;

    // Events
    event TokenMinted(address indexed to, uint256 indexed tokenId, Tier tier);
    event SaleStateChanged(bool active);
    event TierPriceUpdated(Tier tier, uint256 price);

    /**
     * @dev Constructor
     * @param initialOwner The owner of the contract
     * @param baseURI Base URI for token metadata
     */
    constructor(address initialOwner, string memory baseURI) ERC721("CNS Access NFT", "CNSNFT") Ownable(initialOwner) {
        _baseTokenURI = baseURI;
    }

    /**
     * @dev Set the base URI for token metadata
     */
    function setBaseURI(string memory baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
    }

    /**
     * @dev Set tier prices
     */
    function setTierPrices(uint256 _tier1Price, uint256 _tier2Price, uint256 _tier3Price) external onlyOwner {
        tier1Price = _tier1Price;
        tier2Price = _tier2Price;
        tier3Price = _tier3Price;

        emit TierPriceUpdated(Tier.TIER1, _tier1Price);
        emit TierPriceUpdated(Tier.TIER2, _tier2Price);
        emit TierPriceUpdated(Tier.TIER3, _tier3Price);
    }

    /**
     * @dev Toggle sale state
     */
    function toggleSale() external onlyOwner {
        saleActive = !saleActive;
        emit SaleStateChanged(saleActive);
    }

    /**
     * @dev Mint NFT for a specific tier
     * @param to Address to mint to
     * @param tier The tier to mint
     */
    function mintTier(address to, Tier tier) external onlyOwner {
        require(tier != Tier.NONE, "CNSAccessNFT: invalid tier");
        require(tierMinted[tier] < _getTierLimit(tier), "CNSAccessNFT: tier sold out");

        _mintNFT(to, tier);
    }

    /**
     * @dev Buy NFT for a specific tier
     * @param tier The tier to buy
     */
    function buyTier(Tier tier) external payable nonReentrant {
        require(saleActive, "CNSAccessNFT: sale not active");
        require(tier != Tier.NONE, "CNSAccessNFT: invalid tier");
        require(tierMinted[tier] < _getTierLimit(tier), "CNSAccessNFT: tier sold out");
        require(msg.value >= _getTierPrice(tier), "CNSAccessNFT: insufficient payment");

        _mintNFT(msg.sender, tier);

        // Refund excess payment
        if (msg.value > _getTierPrice(tier)) {
            payable(msg.sender).transfer(msg.value - _getTierPrice(tier));
        }
    }

    /**
     * @dev Internal function to mint NFT
     */
    function _mintNFT(address to, Tier tier) internal {
        uint256 tokenId = _nextTokenId++;
        tokenTiers[tokenId] = tier;
        tierMinted[tier]++;
        tierCounts[tier]++;

        _mint(to, tokenId);

        // Set token URI
        _setTokenURI(tokenId, string(abi.encodePacked(_baseTokenURI, uint256(tier))));

        emit TokenMinted(to, tokenId, tier);

        // Update sold out states
        _updateSoldOutStates();
    }

    /**
     * @dev Update sold out states
     */
    function _updateSoldOutStates() internal {
        tier1SoldOut = tierMinted[Tier.TIER1] >= TIER1_LIMIT;
        tier2SoldOut = tierMinted[Tier.TIER2] >= TIER2_LIMIT;
        tier3SoldOut = tierMinted[Tier.TIER3] >= TIER3_LIMIT;
    }

    /**
     * @dev Get tier price
     */
    function _getTierPrice(Tier tier) internal view returns (uint256) {
        if (tier == Tier.TIER1) return tier1Price;
        if (tier == Tier.TIER2) return tier2Price;
        if (tier == Tier.TIER3) return tier3Price;
        return 0;
    }

    /**
     * @dev Get tier limit
     */
    function _getTierLimit(Tier tier) internal pure returns (uint256) {
        if (tier == Tier.TIER1) return TIER1_LIMIT;
        if (tier == Tier.TIER2) return TIER2_LIMIT;
        if (tier == Tier.TIER3) return TIER3_LIMIT;
        return 0;
    }

    /**
     * @dev Get current tier for an address (highest tier they own)
     */
    function getUserTier(address user) public view returns (Tier) {
        Tier highestTier = Tier.NONE;

        // Check all tokens owned by user
        for (uint256 i = 1; i < _nextTokenId; i++) {
            if (_ownerOf(i) == user) {
                Tier tokenTier = tokenTiers[i];
                if (tokenTier > highestTier) {
                    highestTier = tokenTier;
                }
            }
        }

        return highestTier;
    }

    /**
     * @dev Check if user has access to a specific tier
     */
    function hasTierAccess(address user, Tier requiredTier) public view returns (bool) {
        Tier userTier = getUserTier(user);
        return uint256(userTier) >= uint256(requiredTier);
    }

    /**
     * @dev Get tokens owned by address for a specific tier
     */
    function getTokensByTier(address owner, Tier tier) public view returns (uint256[] memory) {
        uint256 tokenCount = balanceOf(owner);
        uint256[] memory tokens = new uint256[](tokenCount);
        uint256 foundCount = 0;

        for (uint256 i = 1; i < _nextTokenId; i++) {
            if (_ownerOf(i) == owner && tokenTiers[i] == tier) {
                tokens[foundCount] = i;
                foundCount++;

                if (foundCount == tokenCount) break;
            }
        }

        // Resize array to actual size
        uint256[] memory result = new uint256[](foundCount);
        for (uint256 i = 0; i < foundCount; i++) {
            result[i] = tokens[i];
        }

        return result;
    }

    /**
     * @dev Withdraw contract balance
     */
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "CNSAccessNFT: no balance to withdraw");

        payable(owner()).transfer(balance);
    }

    /**
     * @dev Override tokenURI to use base URI
     */
    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    /**
     * @dev Override supportsInterface
     */
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Get tier statistics
     */
    function getTierStats()
        external
        view
        returns (
            uint256 tier1Minted,
            uint256 tier2Minted,
            uint256 tier3Minted,
            bool tier1Sold,
            bool tier2Sold,
            bool tier3Sold
        )
    {
        return (
            tierMinted[Tier.TIER1],
            tierMinted[Tier.TIER2],
            tierMinted[Tier.TIER3],
            tier1SoldOut,
            tier2SoldOut,
            tier3SoldOut
        );
    }
}

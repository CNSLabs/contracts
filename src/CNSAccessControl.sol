// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title CNSAccessControl
 * @dev Integration contract that combines NFT access control with tier progression
 * This contract acts as a bridge between the access NFT and tier progression contracts
 */
contract CNSAccessControl is Ownable, ReentrancyGuard {
    // Access NFT contract interface
    struct AccessNFTContract {
        address nftContract;
        bool isActive;
    }

    // Tier definitions
    enum Tier {
        NONE,
        TIER3,
        TIER2,
        TIER1
    }

    // Sale phase definitions
    enum SalePhase {
        NOT_STARTED,
        TIER1_ONLY,
        TIER12,
        ALL_TIERS,
        ENDED
    }

    // Access control contracts
    AccessNFTContract public accessNFT;
    address public tierProgression;

    // Events
    event AccessNFTUpdated(address indexed nftContract, bool active);
    event TierProgressionUpdated(address indexed progressionContract);
    event AccessGranted(address indexed user, Tier tier, SalePhase phase);
    event AccessDenied(address indexed user, Tier tier, SalePhase phase);

    /**
     * @dev Constructor
     * @param initialOwner The owner of the contract
     * @param _accessNFT Address of the access NFT contract
     * @param _tierProgression Address of the tier progression contract
     */
    constructor(address initialOwner, address _accessNFT, address _tierProgression) Ownable(initialOwner) {
        accessNFT = AccessNFTContract(_accessNFT, true);
        tierProgression = _tierProgression;
    }

    /**
     * @dev Update access NFT contract
     */
    function setAccessNFT(address _accessNFT, bool _active) external onlyOwner {
        require(_accessNFT != address(0), "CNSAccessControl: invalid NFT address");
        accessNFT = AccessNFTContract(_accessNFT, _active);
        emit AccessNFTUpdated(_accessNFT, _active);
    }

    /**
     * @dev Update tier progression contract
     */
    function setTierProgression(address _tierProgression) external onlyOwner {
        require(_tierProgression != address(0), "CNSAccessControl: invalid progression address");
        tierProgression = _tierProgression;
        emit TierProgressionUpdated(_tierProgression);
    }

    /**
     * @dev Check if user has access to purchase tokens
     * @param user Address to check
     */
    function hasPurchaseAccess(address user) public view returns (bool, Tier, SalePhase) {
        if (!accessNFT.isActive) {
            return (false, Tier.NONE, SalePhase.NOT_STARTED);
        }

        // Get current phase from tier progression contract
        SalePhase currentPhase = _getCurrentPhase();

        if (currentPhase == SalePhase.NOT_STARTED || currentPhase == SalePhase.ENDED) {
            return (false, Tier.NONE, currentPhase);
        }

        // Get user's tier from access NFT contract
        Tier userTier = _getUserTier(user);

        if (userTier == Tier.NONE) {
            return (false, Tier.NONE, currentPhase);
        }

        // Check if user's tier has access to current phase
        bool hasAccess = _hasTierAccess(userTier, currentPhase);

        return (hasAccess, userTier, currentPhase);
    }

    /**
     * @dev Get detailed access information for a user
     */
    function getAccessInfo(address user)
        external
        view
        returns (
            bool hasAccess,
            Tier userTier,
            SalePhase currentPhase,
            uint256 timeUntilNextPhase,
            Tier[] memory allowedTiers,
            bool isActive
        )
    {
        (hasAccess, userTier, currentPhase) = hasPurchaseAccess(user);

        if (tierProgression != address(0)) {
            // Get time until next phase from tier progression contract
            timeUntilNextPhase = _getTimeUntilNextPhase();

            // Get allowed tiers for current phase
            allowedTiers = _getAllowedTiers(currentPhase);
        } else {
            timeUntilNextPhase = 0;
            allowedTiers = new Tier[](0);
        }

        isActive = accessNFT.isActive && tierProgression != address(0);
    }

    /**
     * @dev Get user's highest tier
     * This calls the access NFT contract to get the user's tier
     */
    function _getUserTier(address user) internal view returns (Tier) {
        if (accessNFT.nftContract == address(0)) {
            return Tier.NONE;
        }

        // In a real implementation, you'd call the CNSAccessNFT contract
        // For now, return NONE to indicate the interface needs to be implemented
        return Tier.NONE;
    }

    /**
     * @dev Get current sale phase from tier progression contract
     */
    function _getCurrentPhase() internal view returns (SalePhase) {
        if (tierProgression == address(0)) {
            return SalePhase.NOT_STARTED;
        }

        // In a real implementation, you'd call the CNSTierProgression contract
        // For now, return NOT_STARTED to indicate the interface needs to be implemented
        return SalePhase.NOT_STARTED;
    }

    /**
     * @dev Get time until next phase
     */
    function _getTimeUntilNextPhase() internal view returns (uint256) {
        if (tierProgression == address(0)) {
            return 0;
        }

        // In a real implementation, you'd call the CNSTierProgression contract
        return 0;
    }

    /**
     * @dev Get allowed tiers for current phase
     */
    function _getAllowedTiers(SalePhase phase) internal view returns (Tier[] memory) {
        if (tierProgression == address(0)) {
            return new Tier[](0);
        }

        // In a real implementation, you'd call the CNSTierProgression contract
        // For now, return empty array
        return new Tier[](0);
    }

    /**
     * @dev Check if a tier has access to a specific phase
     */
    function _hasTierAccess(Tier userTier, SalePhase phase) internal pure returns (bool) {
        if (phase == SalePhase.TIER1_ONLY) {
            return userTier == Tier.TIER1;
        } else if (phase == SalePhase.TIER12) {
            return userTier == Tier.TIER1 || userTier == Tier.TIER2;
        } else if (phase == SalePhase.ALL_TIERS) {
            return userTier == Tier.TIER1 || userTier == Tier.TIER2 || userTier == Tier.TIER3;
        }

        return false;
    }

    /**
     * @dev Emergency disable access control
     */
    function emergencyDisable() external onlyOwner {
        accessNFT.isActive = false;
    }

    /**
     * @dev Emergency enable access control
     */
    function emergencyEnable() external onlyOwner {
        accessNFT.isActive = true;
    }

    /**
     * @dev Check contract health
     */
    function isHealthy() external view returns (bool) {
        return accessNFT.isActive && tierProgression != address(0);
    }

    /**
     * @dev Get contract addresses
     */
    function getContractAddresses() external view returns (address, address) {
        return (accessNFT.nftContract, tierProgression);
    }
}

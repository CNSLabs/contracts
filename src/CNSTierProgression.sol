// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title CNSTierProgression
 * @dev Manages time-based tier progression for token sale access
 * - Day 1: Tier 1 only
 * - Days 2-3: Tiers 1 & 2
 * - Days 4+: All tiers (1, 2, 3)
 */
contract CNSTierProgression is Ownable, ReentrancyGuard {
    // Tier definitions (matching CNSAccessNFT)
    enum Tier {
        NONE,
        TIER1,
        TIER2,
        TIER3
    }

    // Sale phases
    enum SalePhase {
        NOT_STARTED,
        TIER1_ONLY,
        TIER12,
        ALL_TIERS,
        ENDED
    }

    // Phase durations (in seconds)
    uint256 public constant TIER1_ONLY_DURATION = 1 days; // Day 1
    uint256 public constant TIER12_DURATION = 2 days; // Days 2-3
    uint256 public constant ALL_TIERS_DURATION = 7 days; // Days 4-10

    // Sale start time
    uint256 public saleStartTime;

    // Access control contract
    address public accessNFT;

    // Events
    event SaleStarted(uint256 startTime);
    event SalePhaseChanged(SalePhase phase);
    event AccessNFTSet(address indexed nftContract);

    /**
     * @dev Constructor
     * @param initialOwner The owner of the contract
     * @param _accessNFT Address of the access NFT contract
     */
    constructor(address initialOwner, address _accessNFT) Ownable(initialOwner) {
        accessNFT = _accessNFT;
    }

    /**
     * @dev Set the access NFT contract address
     * @param _accessNFT Address of the access NFT contract
     */
    function setAccessNFT(address _accessNFT) external onlyOwner {
        require(_accessNFT != address(0), "CNSTierProgression: invalid NFT address");
        accessNFT = _accessNFT;
        emit AccessNFTSet(_accessNFT);
    }

    /**
     * @dev Start the sale
     * @param startTime Timestamp when sale starts
     */
    function startSale(uint256 startTime) external onlyOwner {
        require(saleStartTime == 0, "CNSTierProgression: sale already started");
        require(startTime > block.timestamp, "CNSTierProgression: start time must be in future");

        saleStartTime = startTime;
        emit SaleStarted(startTime);
    }

    /**
     * @dev Get current sale phase
     */
    function getCurrentPhase() public view returns (SalePhase) {
        if (saleStartTime == 0) {
            return SalePhase.NOT_STARTED;
        }

        uint256 timeElapsed = block.timestamp - saleStartTime;

        if (timeElapsed < TIER1_ONLY_DURATION) {
            return SalePhase.TIER1_ONLY;
        } else if (timeElapsed < TIER1_ONLY_DURATION + TIER12_DURATION) {
            return SalePhase.TIER12;
        } else if (timeElapsed < TIER1_ONLY_DURATION + TIER12_DURATION + ALL_TIERS_DURATION) {
            return SalePhase.ALL_TIERS;
        } else {
            return SalePhase.ENDED;
        }
    }

    /**
     * @dev Check if a tier has access to current phase
     * @param tier The tier to check
     */
    function hasTierAccess(Tier tier) public view returns (bool) {
        SalePhase currentPhase = getCurrentPhase();

        if (currentPhase == SalePhase.NOT_STARTED || currentPhase == SalePhase.ENDED) {
            return false;
        }

        if (currentPhase == SalePhase.TIER1_ONLY) {
            return tier == Tier.TIER1;
        } else if (currentPhase == SalePhase.TIER12) {
            return tier == Tier.TIER1 || tier == Tier.TIER2;
        } else if (currentPhase == SalePhase.ALL_TIERS) {
            return tier == Tier.TIER1 || tier == Tier.TIER2 || tier == Tier.TIER3;
        }

        return false;
    }

    /**
     * @dev Check if an address has access based on their NFT tier
     * @param user Address to check
     */
    function hasUserAccess(address user) public view returns (bool) {
        if (accessNFT == address(0)) {
            return false;
        }

        // Get user's highest tier from the access NFT contract
        // This is a simplified version - in practice, you'd call the access NFT contract
        // For now, we'll assume we can query it directly
        return _getUserHighestTier(user) != Tier.NONE && hasTierAccess(_getUserHighestTier(user));
    }

    /**
     * @dev Get time until next phase
     */
    function getTimeUntilNextPhase() public view returns (uint256, SalePhase) {
        SalePhase currentPhase = getCurrentPhase();

        if (currentPhase == SalePhase.NOT_STARTED) {
            return (saleStartTime > block.timestamp ? saleStartTime - block.timestamp : 0, SalePhase.TIER1_ONLY);
        }

        if (currentPhase == SalePhase.ENDED) {
            return (0, SalePhase.ENDED);
        }

        uint256 timeElapsed = block.timestamp - saleStartTime;
        uint256 timeToNextPhase;

        if (currentPhase == SalePhase.TIER1_ONLY) {
            timeToNextPhase = TIER1_ONLY_DURATION - timeElapsed;
            return (timeToNextPhase, SalePhase.TIER12);
        } else if (currentPhase == SalePhase.TIER12) {
            timeToNextPhase = TIER1_ONLY_DURATION + TIER12_DURATION - timeElapsed;
            return (timeToNextPhase, SalePhase.ALL_TIERS);
        } else if (currentPhase == SalePhase.ALL_TIERS) {
            timeToNextPhase = TIER1_ONLY_DURATION + TIER12_DURATION + ALL_TIERS_DURATION - timeElapsed;
            return (timeToNextPhase, SalePhase.ENDED);
        }

        return (0, currentPhase);
    }

    /**
     * @dev Get phase information
     */
    function getPhaseInfo()
        public
        view
        returns (SalePhase currentPhase, uint256 timeRemaining, SalePhase nextPhase, bool isActive)
    {
        currentPhase = getCurrentPhase();
        (timeRemaining, nextPhase) = getTimeUntilNextPhase();
        isActive = currentPhase != SalePhase.NOT_STARTED && currentPhase != SalePhase.ENDED;

        return (currentPhase, timeRemaining, nextPhase, isActive);
    }

    /**
     * @dev Get allowed tiers for current phase
     */
    function getAllowedTiers() public view returns (Tier[] memory) {
        SalePhase currentPhase = getCurrentPhase();

        if (currentPhase == SalePhase.TIER1_ONLY) {
            Tier[] memory tiers = new Tier[](1);
            tiers[0] = Tier.TIER1;
            return tiers;
        } else if (currentPhase == SalePhase.TIER12) {
            Tier[] memory tiers = new Tier[](2);
            tiers[0] = Tier.TIER1;
            tiers[1] = Tier.TIER2;
            return tiers;
        } else if (currentPhase == SalePhase.ALL_TIERS) {
            Tier[] memory tiers = new Tier[](3);
            tiers[0] = Tier.TIER1;
            tiers[1] = Tier.TIER2;
            tiers[2] = Tier.TIER3;
            return tiers;
        } else {
            Tier[] memory tiers = new Tier[](0);
            return tiers;
        }
    }

    /**
     * @dev Emergency stop (can only be called by owner)
     */
    function emergencyStop() external onlyOwner {
        saleStartTime = 0;
        emit SalePhaseChanged(SalePhase.NOT_STARTED);
    }

    /**
     * @dev Internal function to get user's highest tier
     * In a real implementation, this would call the CNSAccessNFT contract
     */
    function _getUserHighestTier(address user) internal view returns (Tier) {
        // This is a placeholder - in production, you'd call:
        // CNSAccessNFT(accessNFT).getUserTier(user)

        // For now, return NONE to force integration with actual NFT contract
        return Tier.NONE;
    }

    /**
     * @dev Get sale timeline information
     */
    function getSaleTimeline()
        public
        view
        returns (uint256 startTime, uint256 tier1EndTime, uint256 tier12EndTime, uint256 allTiersEndTime)
    {
        startTime = saleStartTime;
        tier1EndTime = saleStartTime + TIER1_ONLY_DURATION;
        tier12EndTime = saleStartTime + TIER1_ONLY_DURATION + TIER12_DURATION;
        allTiersEndTime = saleStartTime + TIER1_ONLY_DURATION + TIER12_DURATION + ALL_TIERS_DURATION;

        return (startTime, tier1EndTime, tier12EndTime, allTiersEndTime);
    }
}

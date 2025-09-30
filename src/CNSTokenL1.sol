// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// OpenZeppelin v5 (non-upgradeable) — smallest, most audited surface area.
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title CanonicalL1Token
 * @notice Fixed-supply ERC20 intended to be the L1 canonical token for bridging to Linea.
 *         The Linea canonical bridge will escrow this token on L1 and mint its L2 representation.
 *         No special bridge logic is required here; standard ERC20 is the most compatible surface.
 *
 *         ERC20Permit (EIP-2612) is included to optionally allow single-tx approvals where supported
 *         (many bridges/wrappers can use permit if available, but it isn't strictly required).
 */
contract CNSTokenL1 is ERC20, ERC20Permit {
    /**
     * @param name_   Token name (also used for EIP-712 domain for Permit)
     * @param symbol_ Token symbol
     * @param initialSupply Recipient of initial fixed supply (minted exactly once)
     * @param initialSupplyRecipient Address that receives the entire fixed supply
     *
     * @dev initialSupply is in wei-style units (respecting 18 decimals by default).
     *      If you need different decimals, override decimals() below before deploy.
     */
    constructor(string memory name_, string memory symbol_, uint256 initialSupply, address initialSupplyRecipient)
        ERC20(name_, symbol_)
        ERC20Permit(name_)
    {
        require(initialSupplyRecipient != address(0), "recipient=0");
        _mint(initialSupplyRecipient, initialSupply);
    }

    // If you need non-18 decimals, uncomment and set a constant.
    // function decimals() public pure override returns (uint8) { return 6; }
}

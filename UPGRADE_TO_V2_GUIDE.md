# CNSTokenL2 V2 Upgrade Guide

This guide explains how to upgrade your deployed CNSTokenL2 contract to V2, which adds governance voting capabilities.

## What's New in V2

CNSTokenL2V2 adds **ERC20Votes** functionality from OpenZeppelin, enabling:

- **Delegation**: Token holders can delegate their voting power to any address
- **Vote Tracking**: Query current and historical voting power
- **Governance Support**: Compatible with governance contracts like OpenZeppelin Governor

### New Functions Available

```solidity
// Delegate voting power
function delegate(address delegatee) external

// Get current voting power
function getVotes(address account) public view returns (uint256)

// Get voting power at a specific block
function getPastVotes(address account, uint256 blockNumber) public view returns (uint256)

// Get total supply at a specific block
function getPastTotalSupply(uint256 blockNumber) public view returns (uint256)

// Get current delegates
function delegates(address account) public view returns (address)

// Clock mode (uses block numbers)
function clock() public view returns (uint48)
function CLOCK_MODE() public view returns (string memory)
```

## Important Notes

### All V1 Features Maintained
- ✅ Bridging functionality (mint/burn via Linea bridge)
- ✅ Pausability
- ✅ Allowlist controls
- ✅ Role-based access control
- ✅ Upgradeability

### Key Behaviors

1. **Voting Power Requires Delegation**: Token holders must explicitly delegate (even to themselves) to activate voting power
2. **Automatic Tracking**: Once delegated, voting power automatically updates on transfers
3. **Allowlist Still Enforced**: All transfers still require both sender and receiver to be allowlisted

## Prerequisites

Before upgrading, ensure you have:

1. The proxy contract address of your deployed CNSTokenL2
2. **The private key of an account with UPGRADER_ROLE** (this is typically the `CNS_OWNER` address from deployment)
3. Environment variables configured

⚠️ **Important**: The account you use for the upgrade must have `UPGRADER_ROLE` on the proxy contract. During initial deployment, this role was granted to the `CNS_OWNER` address, not necessarily the deployer.

## Step 1: Configure Environment

Add to your `.env` file:

```bash
# Your existing variables
PRIVATE_KEY=your_private_key_with_upgrader_role  # Must be CNS_OWNER or have UPGRADER_ROLE
LINEA_SEPOLIA_RPC_URL=https://rpc.sepolia.linea.build

# Add the proxy address
CNS_TOKEN_L2_PROXY=0xYourProxyAddressHere
```

### Checking if You Have UPGRADER_ROLE

You can verify if your account has the required role:

```bash
# Get the UPGRADER_ROLE hash
cast keccak "UPGRADER_ROLE"
# Output: 0x189ab7a9244df0848122154315af71fe140f3db0fe014031783b0946b8c9d2e3

# Check if your account has the role
cast call $CNS_TOKEN_L2_PROXY \
  "hasRole(bytes32,address)" \
  0x189ab7a9244df0848122154315af71fe140f3db0fe014031783b0946b8c9d2e3 \
  YOUR_ADDRESS \
  --rpc-url $LINEA_SEPOLIA_RPC_URL
# Output: 0x0000000000000000000000000000000000000000000000000000000000000001 (true)
#     or: 0x0000000000000000000000000000000000000000000000000000000000000000 (false)
```

### Granting UPGRADER_ROLE (if needed)

If you don't have the role, you need someone with `DEFAULT_ADMIN_ROLE` to grant it:

```bash
cast send $CNS_TOKEN_L2_PROXY \
  "grantRole(bytes32,address)" \
  0x189ab7a9244df0848122154315af71fe140f3db0fe014031783b0946b8c9d2e3 \
  YOUR_ADDRESS \
  --private-key $ADMIN_PRIVATE_KEY \
  --rpc-url $LINEA_SEPOLIA_RPC_URL
```

## Step 2: Run the Upgrade Script

Execute the upgrade script:

```bash
# Using network alias (recommended - defined in foundry.toml)
forge script script/3_UpgradeCNSTokenL2ToV2.s.sol:UpgradeCNSTokenL2ToV2 \
  --rpc-url linea_sepolia \
  --broadcast \
  --verify

# Or using explicit RPC URL
forge script script/3_UpgradeCNSTokenL2ToV2.s.sol:UpgradeCNSTokenL2ToV2 \
  --rpc-url https://rpc.sepolia.linea.build \
  --broadcast \
  --verify

# For local testing with Anvil
forge script script/3_UpgradeCNSTokenL2ToV2.s.sol:UpgradeCNSTokenL2ToV2 \
  --rpc-url http://localhost:8545 \
  --broadcast
```

The script automatically:
1. Detects which network you're deploying to (via chain ID)
2. Checks if you have UPGRADER_ROLE (fails fast with helpful error if not)
3. Deploys the new CNSTokenL2V2 implementation
4. Upgrades the proxy to point to the new implementation
5. Initializes the V2 features (ERC20Votes)
6. Verifies the upgrade succeeded
7. Provides network-specific verification commands

## Step 3: Verify on Block Explorer

After deployment, verify the new implementation contract:

```bash
forge verify-contract <NEW_IMPLEMENTATION_ADDRESS> \
  src/CNSTokenL2V2.sol:CNSTokenL2V2 \
  --chain linea-sepolia \
  --watch
```

## Testing Locally

Before upgrading on testnet/mainnet, test the upgrade locally:

```bash
# Run the upgrade tests
forge test --match-path test/CNSTokenL2V2.t.sol -vv

# Run all tests to ensure nothing broke
forge test
```

## Using V2 Features

### Example: Self-Delegation

```solidity
// User must be allowlisted first
CNSTokenL2V2 token = CNSTokenL2V2(proxyAddress);

// Delegate to yourself to activate voting power
token.delegate(msg.sender);

// Now you have voting power equal to your balance
uint256 votingPower = token.getVotes(msg.sender);
```

### Example: Delegate to Another Address

```solidity
// Delegate to another address (e.g., a governance contract or trusted party)
token.delegate(governorAddress);

// Your tokens stay in your wallet, but voting power goes to the delegate
```

### Example: Query Historical Voting Power

```solidity
// Get voting power at a specific block (useful for governance proposals)
uint256 blockNumber = 12345678;
uint256 historicalVotes = token.getPastVotes(voterAddress, blockNumber);
```

## Rollback Plan

If issues are discovered post-upgrade, the UPGRADER_ROLE can downgrade back to V1:

```solidity
// Deploy V1 implementation again if needed
CNSTokenL2 implementationV1 = new CNSTokenL2();

// Downgrade (no initialization needed since V1 data is still there)
proxy.upgradeTo(address(implementationV1));
```

## Security Considerations

1. **Upgrader Role**: Only addresses with UPGRADER_ROLE can perform upgrades
2. **Delegation is Optional**: Users who don't delegate have zero voting power but can still transfer/use tokens normally
3. **Gas Costs**: Transfers are slightly more expensive due to voting power tracking
4. **Storage**: V2 uses additional storage slots for vote tracking (storage gap reduced accordingly)

## Comparison: V1 vs V2

| Feature | V1 | V2 |
|---------|----|----|
| ERC20 | ✅ | ✅ |
| ERC20Permit | ✅ | ✅ |
| Bridge Support | ✅ | ✅ |
| Pausable | ✅ | ✅ |
| Allowlist | ✅ | ✅ |
| Access Control | ✅ | ✅ |
| Upgradeable (UUPS) | ✅ | ✅ |
| **Voting/Delegation** | ❌ | ✅ |
| **Historical Balance Queries** | ❌ | ✅ |
| **Checkpointing** | ❌ | ✅ |

## Additional Resources

- [OpenZeppelin ERC20Votes Documentation](https://docs.openzeppelin.com/contracts/4.x/api/token/erc20#ERC20Votes)
- [OpenZeppelin Governor Documentation](https://docs.openzeppelin.com/contracts/4.x/api/governance)
- [EIP-2612: Permit Extension](https://eips.ethereum.org/EIPS/eip-2612)

## Support

If you encounter issues during the upgrade:

1. Check that you have UPGRADER_ROLE on the proxy
2. Verify environment variables are correctly set
3. Run tests locally first: `forge test --match-path test/CNSTokenL2V2.t.sol -vv`
4. Review the upgrade transaction on the block explorer

## Files Reference

- **Implementation**: `src/CNSTokenL2V2.sol`
- **Upgrade Script**: `script/3_UpgradeCNSTokenL2ToV2.s.sol`
- **Tests**: `test/CNSTokenL2V2.t.sol`


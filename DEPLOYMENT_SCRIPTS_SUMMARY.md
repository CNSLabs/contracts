# Deployment Scripts Refactoring Summary

## What Changed

### 1. Created BaseScript Utility (New)
- **File**: `script/BaseScript.sol`
- **Purpose**: Shared utilities to eliminate code duplication
- **Features**:
  - Chain ID constants
  - Network detection helpers
  - Validation functions
  - Verification command generation
  - Mainnet safety checks

### 2. Split Multi-Chain Script into Separate Scripts

**Old Approach:**
- Single `DeployCNSContracts.s.sol` deployed both L1 and L2 using fork pattern
- Less flexible, harder to test individually

**New Approach:**
- `1_DeployCNSTokenL1.s.sol` - Deploy L1 token independently
- `2_DeployCNSTokenL2.s.sol` - Deploy L2 token independently
- `DeployCNSContracts.s.sol` - (Legacy, kept for reference)

### 3. Updated All Scripts to Use BaseScript

**Scripts Updated:**
- ✅ `3_UpgradeCNSTokenL2ToV2.s.sol` - Removed ~50 lines of duplication
- ✅ `DemoV2Features.s.sol` - Removed ~10 lines of duplication
- ✅ `1_DeployCNSTokenL1.s.sol` - New, uses BaseScript
- ✅ `2_DeployCNSTokenL2.s.sol` - Recreated, uses BaseScript

## Benefits

### 🎯 Flexibility
- Deploy L1 and L2 independently
- Use `--rpc-url` parameter for any network
- Works with local dev chains (Anvil)

### 🔄 Reduced Duplication
- Network detection logic in one place
- Verification commands auto-generated
- Validation helpers reused across all scripts

### 🛡️ Safety
- Built-in mainnet confirmation
- Address validation before deployment
- Contract verification after deployment

### 📝 Better Documentation
- Clear usage examples in each script
- Comprehensive README in script directory
- Deployment workflow guide

## Usage Examples

### Deploy L1 Token
```bash
forge script script/1_DeployCNSTokenL1.s.sol:DeployCNSTokenL1 \
  --rpc-url sepolia \
  --broadcast \
  --verify
```

### Deploy L2 Token
```bash
# After L1 is deployed and CNS_TOKEN_L1 is set
forge script script/2_DeployCNSTokenL2.s.sol:DeployCNSTokenL2 \
  --rpc-url linea_sepolia \
  --broadcast \
  --verify
```

### Upgrade L2 to V2
```bash
forge script script/3_UpgradeCNSTokenL2ToV2.s.sol:UpgradeCNSTokenL2ToV2 \
  --rpc-url linea_sepolia \
  --broadcast \
  --verify
```

## File Structure

```
script/
├── BaseScript.sol                    # New: Shared utilities
├── 1_DeployCNSTokenL1.s.sol         # New: L1 deployment
├── 2_DeployCNSTokenL2.s.sol         # Recreated: L2 deployment
├── 3_UpgradeCNSTokenL2ToV2.s.sol    # Updated: Uses BaseScript
├── DemoV2Features.s.sol             # Updated: Uses BaseScript
├── DeployCNSContracts.s.sol         # Legacy: Multi-chain deployment
├── verify_cns_contracts.sh          # Unchanged
└── README.md                         # Updated: New workflow
```

## Environment Variables

### Required for L1 Deployment
```bash
PRIVATE_KEY=0x...
CNS_OWNER=0x...
```

### Required for L2 Deployment
```bash
PRIVATE_KEY=0x...
CNS_OWNER=0x...
CNS_TOKEN_L1=0x...              # From L1 deployment
LINEA_L2_BRIDGE=0x...           # Network-specific
```

### Required for Upgrades
```bash
PRIVATE_KEY=0x...               # Must have UPGRADER_ROLE
CNS_TOKEN_L2_PROXY=0x...        # From L2 deployment
```

## Deployment Workflow

1. **Deploy L1** → Get `CNS_TOKEN_L1` address
2. **Deploy L2** → Get `CNS_TOKEN_L2_PROXY` address  
3. **Configure** → Set allowlist, test bridging
4. **Upgrade** (optional) → Add voting features with V2

## Testing

All scripts can be tested locally:

```bash
# Start Anvil
anvil

# Deploy to local chain
forge script script/1_DeployCNSTokenL1.s.sol:DeployCNSTokenL1 \
  --rpc-url http://localhost:8545 \
  --broadcast
```

## Migration from Old Scripts

If you were using `DeployCNSContracts.s.sol`:

**Before:**
```bash
forge script script/DeployCNSContracts.s.sol:DeployCNSContracts --broadcast
```

**After:**
```bash
# Step 1: Deploy L1
forge script script/1_DeployCNSTokenL1.s.sol:DeployCNSTokenL1 \
  --rpc-url sepolia --broadcast --verify

# Step 2: Set CNS_TOKEN_L1 in .env

# Step 3: Deploy L2
forge script script/2_DeployCNSTokenL2.s.sol:DeployCNSTokenL2 \
  --rpc-url linea_sepolia --broadcast --verify
```

## Documentation

- **`script/README.md`** - Quick reference for all scripts
- **`DEPLOYMENT_BEST_PRACTICES.md`** - Comprehensive guide
- **`DEPLOYMENT_SCRIPTS_SUMMARY.md`** - This file

## Next Steps

1. ✅ All scripts compile successfully
2. ✅ Test deployment on Sepolia
3. ✅ Verify contracts on block explorer
4. ✅ Test upgrade path L2 V1 → V2
5. ⏳ Deploy to mainnet (when ready)

## Notes

- The old `DeployCNSContracts.s.sol` is kept for reference but marked as legacy
- All new scripts follow Foundry best practices
- Scripts work on any EVM network via `--rpc-url` parameter
- BaseScript can be extended for future deployment scripts


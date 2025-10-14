# CNS Token L2 Upgrade Script

This folder contains a single, comprehensive upgrade script that handles the complete upgrade process for CNS Token L2 with whitelist toggle functionality.

## Quick Start

```bash
# 1. Configure your parameters
source script/upgrade/input_params.env

# 2. Run the upgrade script
forge script script/upgrade/UpgradeToken.s.sol:UpgradeToken --rpc-url $RPC_URL --broadcast
```

That's it! The script handles everything automatically with clear visual progress indicators.

## What This Script Does

The `UpgradeToken.s.sol` script performs all upgrade steps in sequence:

1. ✅ **Validate Input Parameters** - Checks all required environment variables
2. ✅ **Validate Target Contract** - Verifies the target is a valid UUPS proxy
3. ✅ **Check Upgrader Permissions** - Ensures upgrader has UPGRADER_ROLE
4. ✅ **Detect Upgrader Type** - Determines if upgrader is Safe or EOA
5. ✅ **Deploy New Implementation** - Deploys the new contract with whitelist toggle
6. ✅ **Prepare Upgrade Transaction** - Generates transaction data for execution
7. ✅ **Provide Execution Instructions** - Shows how to complete the upgrade

## Configuration

Edit `input_params.env` with your deployment details:

```bash
# Target contract (proxy) to upgrade
TARGET_CONTRACT=0xe666C12f3C6Cba29350146A883131cAc5659758F

# Upgrader address (must have UPGRADER_ROLE)
UPGRADER_ADDRESS=0xD7C8FD8F38683110B15771392Eb74209c15495ac

# Network RPC URL
RPC_URL=https://rpc.sepolia.linea.build

# Gas limit for upgrade transaction
GAS_LIMIT=500000
```

## Visual Progress Tracking

The script provides beautiful visual feedback throughout the process:

```
################################################################
##                                                            ##
##         CNS TOKEN L2 UPGRADE - ALL-IN-ONE SCRIPT           ##
##                                                            ##
################################################################

================================================================
  STEP 1 of 7: VALIDATE INPUT PARAMETERS
================================================================

[SUCCESS] Input parameters validated
Progress: 1/7 steps completed

----------------------------------------------------------------
Overall Progress: 14% (1/7 steps)
----------------------------------------------------------------
```

Each step shows:
- Clear step headers with step number
- Success/error indicators
- Current progress (e.g., "1/7 steps completed")
- Overall percentage completion (e.g., "14%")

## For Safe Upgraders

If your upgrader is a Gnosis Safe, the script will:
1. Deploy the new implementation
2. Generate Safe transaction data
3. Provide step-by-step Safe UI instructions

Example output:
```
SAFE EXECUTION REQUIRED

Execute the upgrade via Safe UI:

1. Go to: https://app.safe.global/
2. Select Safe: 0xD7C8FD8F38683110B15771392Eb74209c15495ac
3. New Transaction -> Contract Interaction
4. Contract address: 0xe666C12f3C6Cba29350146A883131cAc5659758F
5. Transaction data: 0x4f1ef286...
6. Gas limit: 500000
7. Review and submit for signatures
```

## For EOA Upgraders

If your upgrader is an EOA (Externally Owned Account), the script will provide instructions for direct execution using `cast` or other methods.

**Note**: For safety, the script does NOT automatically execute upgrades. You must manually execute using the provided transaction data.

## Complete Example

```bash
# Step 1: Load your configuration
source script/upgrade/input_params.env

# Step 2: Run the upgrade script
forge script script/upgrade/UpgradeToken.s.sol:UpgradeToken \
  --rpc-url $RPC_URL \
  --broadcast

# Step 3: Follow the on-screen instructions to complete the upgrade
# - For Safe: Use Safe UI with the provided transaction data
# - For EOA: Use cast or execute manually
```

## Post-Upgrade Verification

After successful upgrade, verify the new functionality:

```bash
# Check if whitelist toggle function exists
cast call $TARGET_CONTRACT "senderAllowlistEnabled()" --rpc-url $RPC_URL

# Expected output: 0x0000000000000000000000000000000000000000000000000000000000000001 (true)
```

Test the whitelist toggle:
```bash
# Toggle the whitelist (requires ALLOWLIST_ADMIN_ROLE)
cast send $TARGET_CONTRACT \
  "setSenderAllowlistEnabled(bool)" \
  false \
  --private-key <admin_key> \
  --rpc-url $RPC_URL
```

## Troubleshooting

### Common Issues

**1. Missing UPGRADER_ROLE**
```
ERROR: Upgrader does not have UPGRADER_ROLE
```
Solution: Grant the role to your upgrader address. The script will show the exact command to run.

**2. Contract Not Found**
```
ERROR: No contract found at target address
```
Solution: Verify `TARGET_CONTRACT` address is correct in `input_params.env`

**3. Not a Proxy**
```
ERROR: Target contract is not a proxy
```
Solution: Ensure `TARGET_CONTRACT` points to the proxy, not the implementation

**4. Environment Variables Not Set**
```
ERROR: TARGET_CONTRACT not set
```
Solution: Make sure you ran `source script/upgrade/input_params.env`

### Debug Tips

1. **Check your current configuration**:
   ```bash
   echo $TARGET_CONTRACT
   echo $UPGRADER_ADDRESS
   echo $RPC_URL
   ```

2. **Verify the upgrader has the correct role**:
   ```bash
   UPGRADER_ROLE=$(cast keccak "UPGRADER_ROLE")
   cast call $TARGET_CONTRACT \
     "hasRole(bytes32,address)(bool)" \
     $UPGRADER_ROLE \
     $UPGRADER_ADDRESS \
     --rpc-url $RPC_URL
   ```

3. **Check current implementation**:
   ```bash
   cast implementation $TARGET_CONTRACT --rpc-url $RPC_URL
   ```

## What Gets Deployed

The script deploys a new implementation of `CNSTokenL2` with these new features:

- **`setSenderAllowlistEnabled(bool)`** - Toggle the sender allowlist on/off
- **`senderAllowlistEnabled()`** - Check if the allowlist is currently enabled
- Enhanced allowlist control for better flexibility

The existing functionality remains unchanged:
- Minting, burning, pausing
- Access control roles
- Bridge functionality
- All existing allowlist functions

## Security Notes

- ✅ Always test on testnet before mainnet
- ✅ Verify all contract addresses before executing
- ✅ Use Safe for production upgrades when possible
- ✅ Keep private keys secure and never commit them to version control
- ✅ The script does NOT automatically execute upgrades - you maintain full control

## Script Output Files

After running, the script creates:
- `broadcast/UpgradeToken.s.sol/<chain_id>/run-latest.json` - Transaction details
- `cache/UpgradeToken.s.sol/<chain_id>/run-latest.json` - Sensitive data (gitignored)

These files contain the deployment transaction data and can be used for verification.

## Need Help?

The script provides detailed error messages and instructions at each step. If something fails:
1. Read the error message carefully
2. Follow the suggested actions
3. Check the troubleshooting section above
4. Verify your configuration in `input_params.env`

# UUPS Proxy Upgrade Script

Comprehensive upgrade script for UUPS upgradeable contracts with Safe support.

## Quick Start

```bash
# 1. Configure parameters
source script/upgrade/input_params.env

# 2. Run upgrade
forge script script/upgrade/UpgradeToken.s.sol:UpgradeToken --rpc-url $RPC_URL --broadcast
```

## Process

The script performs:

1. **Validate Parameters** - Checks environment variables
2. **Validate Target** - Verifies UUPS proxy
3. **Check Permissions** - Ensures UPGRADER_ROLE
4. **Detect Upgrader** - Identifies Safe or EOA
5. **Deploy Implementation** - Deploys new contract
6. **Prepare Transaction** - Generates upgrade data
7. **Provide Instructions** - Shows execution steps

## Configuration

Edit `input_params.env`:

```bash
TARGET_CONTRACT=0x...    # Proxy to upgrade
UPGRADER_ADDRESS=0x...   # Must have UPGRADER_ROLE
RPC_URL=https://...      # Network RPC
GAS_LIMIT=500000         # Gas limit
```

## Progress Tracking

Visual feedback provided:

```
================================================================
  STEP 1 of 7: VALIDATE INPUT PARAMETERS
================================================================

[SUCCESS] Input parameters validated
Progress: 1/7 steps completed (14%)
```

## Safe Execution

For Gnosis Safe upgraders:
1. Deploys implementation
2. Generates transaction data
3. Provides Safe UI steps

## EOA Execution

For EOA upgraders, provides `cast` commands for manual execution.

**Note**: Script does not auto-execute upgrades for safety.

## Example

```bash
# Load config
source script/upgrade/input_params.env

# Run script
forge script script/upgrade/UpgradeToken.s.sol:UpgradeToken \
  --rpc-url $RPC_URL \
  --broadcast

# Follow on-screen instructions
```

## Verification

Verify upgrade success:

```bash
# Check new implementation
cast implementation $TARGET_CONTRACT --rpc-url $RPC_URL

# Test new functionality (if applicable)
cast call $TARGET_CONTRACT "newFunction()" --rpc-url $RPC_URL
```

## Troubleshooting

Common issues:

**Missing UPGRADER_ROLE**
```
ERROR: Upgrader does not have UPGRADER_ROLE
```
→ Grant role to upgrader address

**Contract Not Found**
```
ERROR: No contract found at target address
```
→ Verify TARGET_CONTRACT in config

**Not a Proxy**
```
ERROR: Target contract is not a proxy
```
→ Ensure TARGET_CONTRACT is proxy, not implementation

**Env Not Set**
```
ERROR: TARGET_CONTRACT not set
```
→ Run `source script/upgrade/input_params.env`

### Debug Commands

```bash
# Check config
echo $TARGET_CONTRACT $UPGRADER_ADDRESS $RPC_URL

# Verify role
UPGRADER_ROLE=$(cast keccak "UPGRADER_ROLE")
cast call $TARGET_CONTRACT \
  "hasRole(bytes32,address)(bool)" \
  $UPGRADER_ROLE $UPGRADER_ADDRESS \
  --rpc-url $RPC_URL

# Check implementation
cast implementation $TARGET_CONTRACT --rpc-url $RPC_URL
```

## Security

- Test on testnet first
- Verify addresses before execution
- Use Safe for production
- Never commit private keys
- Manual execution required

## Output Files

Generated files:
- `broadcast/UpgradeToken.s.sol/<chain>/run-latest.json` - TX details
- `cache/UpgradeToken.s.sol/<chain>/run-latest.json` - Sensitive data (gitignored)

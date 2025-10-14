# CNS Token L2 Upgrade Scripts

This folder contains scripts for upgrading the CNS Token L2 contract to include whitelist toggle functionality.

## Quick Start: All-in-One Script

For a streamlined upgrade experience, use the all-in-one script that runs all steps sequentially with visual progress indicators:

```bash
# Load environment variables
source script/upgrade/0_input_params.env

# Run the complete upgrade process
forge script script/upgrade/AllInOne_UpgradeCNSTokenL2.s.sol:AllInOne_UpgradeCNSTokenL2 --rpc-url $RPC_URL --broadcast
```

This script will:
- ✅ Validate all inputs
- ✅ Check target contract
- ✅ Verify upgrader permissions
- ✅ Detect upgrader type (Safe/EOA)
- ✅ Deploy new implementation
- ✅ Generate upgrade transaction data
- ✅ Provide execution instructions

**Progress tracking**: Shows percentage completion and step-by-step progress (e.g., "Overall Progress: 57% (4/7 steps)")

## Modular Approach

Alternatively, the upgrade process is broken down into 7 individual scripts for more control:

1. **Validate Inputs** - Check that all required parameters are provided
2. **Validate Target Contract** - Verify the target is a valid UUPS proxy
3. **Check Upgrader Permissions** - Ensure upgrader has UPGRADER_ROLE
4. **Detect Upgrader Type** - Determine if upgrader is Safe or EOA
5. **Deploy Implementation** - Deploy new implementation with whitelist toggle
6. **Prepare Upgrade Transaction** - Generate transaction data for execution
7. **Execute Upgrade** - Execute the upgrade (EOA only)

## Setup

1. **Copy and configure the environment file:**
   ```bash
   cp upgrade/0_input_params.env upgrade/my_upgrade.env
   # Edit my_upgrade.env with your specific values
   ```

2. **Set your parameters in the environment file:**
   ```bash
   # Required parameters
   TARGET_CONTRACT=0xe666C12f3C6Cba29350146A883131cAc5659758F
   UPGRADER_ADDRESS=0xD7C8FD8F38683110B15771392Eb74209c15495ac
   RPC_URL=https://rpc.sepolia.linea.build
   
   # Optional parameters
   GAS_LIMIT=500000
   NEW_IMPLEMENTATION=0x...  # Set after Step 5
   ```

## Usage

### For Safe Upgraders (Recommended)

Run steps 1-6 to prepare the upgrade, then execute via Safe UI:

```bash
# Load your environment
source upgrade/my_upgrade.env

# Run validation steps
forge script upgrade/1_ValidateInputs.s.sol:Step1_ValidateInputs --rpc-url $RPC_URL
forge script upgrade/2_ValidateTargetContract.s.sol:Step2_ValidateTargetContract --rpc-url $RPC_URL
forge script upgrade/3_CheckUpgraderPermissions.s.sol:Step3_CheckUpgraderPermissions --rpc-url $RPC_URL
forge script upgrade/4_DetectUpgraderType.s.sol:Step4_DetectUpgraderType --rpc-url $RPC_URL

# Deploy new implementation
forge script upgrade/5_DeployImplementation.s.sol:Step5_DeployImplementation --rpc-url $RPC_URL --broadcast

# Prepare upgrade transaction (add NEW_IMPLEMENTATION to env file first)
forge script upgrade/6_PrepareUpgradeTransaction.s.sol:Step6_PrepareUpgradeTransaction --rpc-url $RPC_URL

# Execute via Safe UI using the transaction data from Step 6
```

### For EOA Upgraders

Run all steps including the execution:

```bash
# Load your environment
source upgrade/my_upgrade.env

# Run all steps
forge script upgrade/1_ValidateInputs.s.sol:Step1_ValidateInputs --rpc-url $RPC_URL
forge script upgrade/2_ValidateTargetContract.s.sol:Step2_ValidateTargetContract --rpc-url $RPC_URL
forge script upgrade/3_CheckUpgraderPermissions.s.sol:Step3_CheckUpgraderPermissions --rpc-url $RPC_URL
forge script upgrade/4_DetectUpgraderType.s.sol:Step4_DetectUpgraderType --rpc-url $RPC_URL
forge script upgrade/5_DeployImplementation.s.sol:Step5_DeployImplementation --rpc-url $RPC_URL --broadcast

# Add NEW_IMPLEMENTATION to your env file, then:
forge script upgrade/6_PrepareUpgradeTransaction.s.sol:Step6_PrepareUpgradeTransaction --rpc-url $RPC_URL
forge script upgrade/7_ExecuteUpgrade.s.sol:Step7_ExecuteUpgrade --rpc-url $RPC_URL --broadcast
```

## Script Details

### Step 1: Validate Inputs
- Checks that all required environment variables are set
- Validates address formats
- Displays parameter summary

### Step 2: Validate Target Contract
- Verifies contract exists at target address
- Confirms it's a proxy with implementation
- Checks implementation is UUPS upgradeable

### Step 3: Check Upgrader Permissions
- Verifies upgrader has UPGRADER_ROLE
- Provides instructions if role is missing

### Step 4: Detect Upgrader Type
- Determines if upgrader is Safe or EOA
- Provides appropriate guidance for each type

### Step 5: Deploy Implementation
- Deploys new CNSTokenL2 implementation
- Includes whitelist toggle functionality
- Saves implementation address for next steps

### Step 6: Prepare Upgrade Transaction
- Generates upgradeToAndCall transaction data
- Provides Safe UI instructions
- Provides EOA execution instructions

### Step 7: Execute Upgrade (EOA Only)
- Executes the upgrade transaction
- Verifies upgrade success
- Provides post-upgrade verification commands

## Verification

After successful upgrade, verify the new functionality:

```bash
# Check if whitelist toggle function exists
cast call $TARGET_CONTRACT "senderAllowlistEnabled()" --rpc-url $RPC_URL

# Test setting whitelist toggle (requires appropriate role)
cast send $TARGET_CONTRACT "setSenderAllowlistEnabled(bool)" true --private-key <key> --rpc-url $RPC_URL
```

## Troubleshooting

### Common Issues

1. **Missing UPGRADER_ROLE**: Run Step 3 to get instructions for granting the role
2. **Contract not found**: Verify TARGET_CONTRACT address is correct
3. **Not a proxy**: Ensure target contract is a UUPS proxy
4. **Private key mismatch**: Ensure private key matches UPGRADER_ADDRESS

### Getting Help

Each script provides detailed error messages and instructions. If a step fails, check the error message and follow the suggested actions.

## Security Notes

- Always verify contract addresses before executing
- Test on testnet before mainnet deployment
- Use Safe for production upgrades when possible
- Keep private keys secure and never commit them to version control

## Features

- **Command Line Input**: Accepts target contract address via environment variable
- **Safe Detection**: Automatically detects if upgrader is a Safe contract
- **Safe Support**: Generates transaction data for Safe execution
- **EOA Support**: Direct execution for EOA upgraders
- **Validation**: Comprehensive validation of target contract and permissions

## Usage

### EOA Upgrader (Direct Execution)

```bash
# Set environment variables
export TARGET_CONTRACT=0x1234567890123456789012345678901234567890
export CNS_OWNER_PRIVATE_KEY=0x...

# Run upgrade script
forge script script/5_UpgradeCNSTokenL2ToWhitelistToggle.s.sol:UpgradeCNSTokenL2ToWhitelistToggle \
  --rpc-url <your_rpc_url> \
  --broadcast
```

### Safe Upgrader (Transaction Preparation)

```bash
# Set environment variables
export TARGET_CONTRACT=0x1234567890123456789012345678901234567890
export CNS_OWNER_PRIVATE_KEY=0x...  # Any private key for gas estimation
export PREPARE_SAFE_TX=true

# Run upgrade script (generates transaction data)
forge script script/5_UpgradeCNSTokenL2ToWhitelistToggle.s.sol:UpgradeCNSTokenL2ToWhitelistToggle \
  --rpc-url <your_rpc_url>
```

## Safe Execution Process

When a Safe is detected, the script will:

1. **Deploy** the new implementation contract
2. **Generate** transaction data for `upgradeToAndCall`
3. **Estimate** gas requirements
4. **Provide** step-by-step instructions for Safe UI
5. **Output** Safe CLI commands as alternative

### Safe UI Instructions

The script outputs detailed instructions for executing the upgrade via Safe UI:

1. Go to [Safe UI](https://app.safe.global/)
2. Connect wallet and select the Safe
3. Click "New Transaction" → "Contract Interaction"
4. Enter the target contract address
5. Paste the generated transaction data
6. Set gas limit as specified
7. Review and submit for signatures

### Safe CLI Alternative

```bash
safe-cli transaction create \
  --to <target_contract> \
  --value 0 \
  --data <generated_data> \
  --gas-limit <estimated_gas>
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `TARGET_CONTRACT` | Yes | Address of the contract to upgrade |
| `CNS_OWNER_PRIVATE_KEY` | No* | Private key with UPGRADER_ROLE |
| `PRIVATE_KEY` | No* | Fallback private key |
| `PREPARE_SAFE_TX` | No | Set to `true` to prepare Safe transaction |
| `MAINNET_DEPLOYMENT_ALLOWED` | Yes** | Set to `true` for mainnet |

*One of `CNS_OWNER_PRIVATE_KEY` or `PRIVATE_KEY` is required  
**Required for mainnet deployments

## Validation

The script performs comprehensive validation:

- ✅ Target contract exists and is upgradeable
- ✅ Upgrader has `UPGRADER_ROLE`
- ✅ Contract is UUPS upgradeable
- ✅ Safe detection and appropriate handling
- ✅ Gas estimation for Safe transactions

## Output

### EOA Upgrade
- Direct execution of upgrade
- Verification of new implementation
- Confirmation of new functionality

### Safe Upgrade
- Transaction data for Safe execution
- Gas estimation
- Step-by-step Safe UI instructions
- Safe CLI commands
- Manual execution guidance

## Example Output

```
=== Safe Upgrade Detected ===
Preparing transaction data for Safe execution...

=== Safe Transaction Data ===
To: 0x1234567890123456789012345678901234567890
Value: 0
Data: 0x3659cfe6000000000000000000000000...
Gas Limit: 500000
Operation: 0 (Call)

=== Safe Execution Instructions ===
1. Go to Safe UI: https://app.safe.global/
2. Connect your wallet and select the Safe
3. Click 'New Transaction' -> 'Contract Interaction'
4. Enter the contract address: 0x1234567890123456789012345678901234567890
5. Paste the transaction data above
6. Set gas limit to: 500000
7. Review and submit for signatures
```

## Security Notes

- Always verify the target contract address
- Ensure the upgrader has the correct permissions
- Review transaction data before execution
- Test on testnet before mainnet deployment
- Use Safe's multi-signature protection for production upgrades

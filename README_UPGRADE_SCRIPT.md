## Features

- **Command Line Input**: Target contract address via environment variable
- **Safe Detection**: Auto-detects Gnosis Safe upgraders
- **Safe Support**: Generates transaction data for Safe UI execution
- **EOA Support**: Direct execution for EOA upgraders
- **Validation**: Validates target contract and upgrader permissions

## Usage

### EOA Upgrader

```bash
export TARGET_CONTRACT=0x...
export OWNER_PRIVATE_KEY=0x...

forge script script/upgrade/UpgradeToken.s.sol:UpgradeToken \
  --rpc-url <rpc_url> \
  --broadcast
```

### Safe Upgrader

```bash
export TARGET_CONTRACT=0x...
export OWNER_PRIVATE_KEY=0x...  # For gas estimation only
export PREPARE_SAFE_TX=true

forge script script/upgrade/UpgradeToken.s.sol:UpgradeToken \
  --rpc-url <rpc_url>
```

## Safe Execution

When a Safe is detected:

1. Deploys new implementation
2. Generates `upgradeToAndCall` transaction data
3. Estimates gas requirements
4. Provides Safe UI instructions

### Safe UI Steps

1. Go to [app.safe.global](https://app.safe.global/)
2. Select your Safe
3. New Transaction → Contract Interaction
4. Enter target contract address
5. Paste transaction data
6. Set gas limit (as specified)
7. Review and submit

### Safe CLI

```bash
safe-cli transaction create \
  --to <target> \
  --value 0 \
  --data <tx_data> \
  --gas-limit <gas>
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `TARGET_CONTRACT` | Yes | Proxy contract address to upgrade |
| `OWNER_PRIVATE_KEY` | No* | Private key with UPGRADER_ROLE |
| `PRIVATE_KEY` | No* | Alternative private key variable |
| `PREPARE_SAFE_TX` | No | Set `true` for Safe transaction prep |
| `MAINNET_DEPLOYMENT_ALLOWED` | Yes** | Must be `true` for mainnet |

*One private key variable required  
**Required for mainnet only

## Validation

Automated checks:

- Target contract exists and is upgradeable
- Upgrader has `UPGRADER_ROLE`
- UUPS proxy pattern verified
- Safe detection and handling
- Gas estimation

## Security

- Verify target address before execution
- Confirm upgrader permissions
- Review transaction data carefully
- Test on testnet first
- Use Safe for production

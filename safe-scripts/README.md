# Safe Transaction Batch Generator

A tool for generating Safe transaction batch JSON files for token bridge operations. This generates the necessary calldata for approve + bridgeToken transactions that can be imported into Safe's transaction builder.

## Installation

```bash
cd safe-scripts
npm install
```

## Token Bridge Batch Script

The main script generates a batch of transactions for bridging tokens from L1 to L2 (or vice versa). It creates two transactions:

1. **Approve** - Approves the bridge contract to spend tokens
2. **Bridge** - Calls `bridgeToken` on the bridge contract

## Vesting Plans Batch Script

The vesting plans script generates a batch of transactions for creating multiple vesting plans using Hedgey's batch planner. It creates two transactions:

1. **Approve** - Approves the batch planner to spend tokens
2. **Batch Create** - Calls `batchVestingPlans` with all plans

### Token Bridge Usage

#### Basic Usage

```bash
# Generate batch for dev environment (testnet)
npm run generate-token-bridge-batch-test

# Generate batch for production environment (mainnet)
npm run generate-token-bridge-batch
```

### Vesting Plans Usage

#### Basic Usage

```bash
# Generate vesting plans batch for dev environment (testnet)
npm run generate-vesting-plans-batch-test

# Generate vesting plans batch for production environment (mainnet)
npm run generate-vesting-plans-batch
```

#### Token Bridge Command Line Options

```bash
# Full command with all options
node src/token-bridge-batch.js [options]

Options:
  -e, --env <environment>        Environment (dev, alpha, production) [default: dev]
  --testnet                      Use testnet chain ID (59141), otherwise mainnet (59144)
  -o, --output <file>            Output file path [default: token-bridge-batch.json]
  --token-holder <address>       Token holder safe address (overrides config)
  --token-contract <address>     Token contract address (overrides config)
  --token-supply <amount>        Token supply amount (overrides config)
  --bridge-contract <address>    Bridge contract address (overrides config)
  --recipient <address>          Recipient address for bridged tokens (overrides config)
  --dry-run                      Print the generated JSON without writing to file
  -h, --help                     Display help for command
```

#### Vesting Plans Command Line Options

```bash
# Full command with all options
node src/create-vesting-plans-batch.js [options]

Options:
  -e, --env <environment>        Environment (dev, alpha, production) [default: dev]
  --testnet                      Use testnet chain ID (59141), otherwise mainnet (59144)
  -o, --output <file>            Output file path [default: vesting-plans-batch.json]
  --token-contract <address>     Token contract address (overrides config)
  --batch-planner <address>      Batch planner contract address (overrides config)
  --vesting-admin <address>      Vesting admin address (overrides config)
  --dry-run                      Print the generated JSON without writing to file
  -h, --help                     Display help for command
```

#### Examples

```bash
# Dry run to see what would be generated
node src/token-bridge-batch.js --env dev --testnet --token-contract 0x1234... --dry-run

# Override specific values
node src/token-bridge-batch.js --env alpha --token-contract 0xabcd... \
  --token-holder 0x1234567890123456789012345678901234567890

# Custom output file
node src/token-bridge-batch.js --env production --token-contract 0x1111... \
  --output production-batch.json
```

## Configuration

The script uses a priority system for configuration values:

1. **Command line arguments** (highest priority)
2. **Environment variables**
3. **Config files** (lowest priority)

### Environment Variables

Set these in your `.env` file or environment:

```bash
# Required addresses
CNS_DEFAULT_ADMIN=0x1234567890123456789012345678901234567890
CNS_TOKEN_L1=0x0987654321098765432109876543210987654321

# Optional overrides
BRIDGE_CONTRACT=0x1111111111111111111111111111111111111111
RECIPIENT_ADDRESS=0x2222222222222222222222222222222222222222
```

### Config Files

The script automatically loads configuration from:
- `config/dev.json`
- `config/alpha.json` 
- `config/production.json`

These files contain chain-specific configuration including:
- Chain IDs
- Token addresses
- Bridge addresses
- Role assignments
- Token supply amounts

## Output Format

The script generates a JSON file compatible with Safe's transaction builder interface:

```json
{
  "version": "1.0",
  "chainId": "1",
  "createdAt": 1703123456789,
  "meta": {
    "name": "Transactions Batch",
    "description": "",
    "txBuilderVersion": "1.18.2",
    "createdFromSafeAddress": "0x1234567890123456789012345678901234567890",
    "createdFromOwnerAddress": "",
    "checksum": ""
  },
  "transactions": [
    {
      "to": "0x0987654321098765432109876543210987654321",
      "value": "0",
      "data": null,
      "contractMethod": {
        "inputs": [
          {
            "internalType": "address",
            "name": "spender",
            "type": "address"
          },
          {
            "internalType": "uint256",
            "name": "value",
            "type": "uint256"
          }
        ],
        "name": "approve",
        "payable": false
      },
      "contractInputsValues": {
        "spender": "0xd19d4B5d358258f05D7B411E21A1460D11B0876F",
        "value": "1000000000000000000000"
      }
    },
    {
      "to": "0xd19d4B5d358258f05D7B411E21A1460D11B0876F",
      "value": "0",
      "data": null,
      "contractMethod": {
        "inputs": [
          {
            "internalType": "address",
            "name": "_token",
            "type": "address"
          },
          {
            "internalType": "uint256",
            "name": "_amount",
            "type": "uint256"
          },
          {
            "internalType": "address",
            "name": "_recipient",
            "type": "address"
          }
        ],
        "name": "bridgeToken",
        "payable": true
      },
      "contractInputsValues": {
        "_token": "0x0987654321098765432109876543210987654321",
        "_amount": "1000000000000000000000",
        "_recipient": "0x1234567890123456789012345678901234567890"
      }
    }
  ]
}
```

## Using the Output

### Import into Safe Transaction Builder

1. **Generate the batch file**:
   ```bash
   npm run generate-token-bridge-batch-test
   ```

2. **Go to Safe Transaction Builder**:
   - Navigate to [Gnosis Safe](https://gnosis-safe.io/app)
   - Select your Safe wallet
   - Go to "Apps" → "Transaction Builder"

3. **Import the file**:
   - Drag and drop the generated JSON file (`out/token-bridge-batch.json`)
   - Or click "Import" and select the file

4. **Review and execute**:
   - Review the transactions
   - Add required signatures
   - Execute the batch

### Programmatic Usage

You can also use the generated JSON programmatically:

```javascript
const batchData = require('./out/token-bridge-batch.json');

// Access individual transactions
const transactions = batchData.transactions;
console.log(`Number of transactions: ${transactions.length}`);

// Access transaction details
const approveTx = transactions[0];
const bridgeTx = transactions[1];
```

## Available Scripts

```bash
# Token bridge scripts
npm run generate-token-bridge-batch        # Generate mainnet token bridge batch
npm run generate-token-bridge-batch-test   # Generate testnet token bridge batch

# Vesting plans scripts
npm run generate-vesting-plans-batch       # Generate mainnet vesting plans batch
npm run generate-vesting-plans-batch-test  # Generate testnet vesting plans batch

# Legacy scripts (for reference)
npm run legacy                             # Run original generate-safe-batch.js
npm start                                  # Run generic batch generator
npm test                                   # Validate configuration
```

## Error Handling

The script validates:
- ✅ All required addresses are valid Ethereum addresses
- ✅ Chain IDs are positive numbers  
- ✅ Token supply amounts are greater than zero
- ✅ Config files exist and are valid JSON
- ✅ All required values are present

## Troubleshooting

**"Token contract address not found"**
- Set `CNS_TOKEN_L1` environment variable
- Or use `--token-contract` command line option
- Or ensure `l2.l1Token` is set in your config file

**"Invalid address"**
- Ensure addresses are valid Ethereum addresses (0x followed by 40 hex characters)
- Check for typos in your variable values

**"Config file not found"**
- Ensure the config file exists in `config/` directory
- Use `--env` option to specify the correct environment

## Dependencies

- `@morpho-labs/gnosis-tx-builder`: Safe transaction builder integration
- `commander`: Command line argument parsing
- `dotenv`: Environment variable loading
- `ethers`: Ethereum utilities and ABI encoding
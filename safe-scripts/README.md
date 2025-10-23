# Safe Batch Generator

This script generates Safe transaction batch JSON files from a template by substituting placeholder values with configuration from environment variables and config files.

## Installation

```bash
cd scripts
npm install
```

## Usage

### Basic Usage

```bash
# Generate batch for dev environment (testnet)
node generate-safe-batch.js --env dev --testnet --token-contract 0x1234...

# Generate batch for alpha environment (mainnet)
node generate-safe-batch.js --env alpha --token-contract 0xabcd...

# Generate batch for production environment (mainnet)
node generate-safe-batch.js --env production --token-contract 0x1111...
```

### Command Line Options

- `-e, --env <environment>`: Environment (dev, alpha, production) [default: dev]
- `--testnet`: Use testnet chain ID (59141), otherwise use mainnet (59144)
- `-o, --output <file>`: Output file path [default: safe-batch.json] (saved to out/ directory)
- `--token-holder <address>`: Token holder safe address (overrides config)
- `--token-contract <address>`: Token contract address (overrides config)
- `--token-supply <amount>`: Token supply amount (overrides config)
- `--bridge-contract <address>`: Bridge contract address (overrides config)
- `--dry-run`: Print the generated JSON without writing to file

### Examples

```bash
# Dry run to see what would be generated
node generate-safe-batch.js --env dev --testnet --token-contract 0x1234... --dry-run

# Override specific values
node generate-safe-batch.js --env alpha --token-contract 0xabcd... \
  --token-holder 0x1234567890123456789012345678901234567890

# Custom output file
node generate-safe-batch.js --env production --token-contract 0x1111... \
  --output production-batch.json
```

## Configuration

The script uses a priority system for configuration values:

1. **Command line arguments** (highest priority)
2. **Environment variables**
3. **Config files** (lowest priority)

### Environment Variables

Set these in your `.env` file or environment:

- `CNS_DEFAULT_ADMIN`: Default admin address (used for token holder safe)
- `CNS_TOKEN_L1`: L1 token contract address
- `CNS_TOKEN_L2_PROXY`: L2 token proxy address
- `LINEA_L1_BRIDGE`: Linea L1 bridge contract address
- `LINEA_L2_BRIDGE`: Linea L2 bridge contract address

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

## Template Structure

The script uses a template that creates a Safe transaction batch with two transactions:

1. **Approve**: Approves the bridge contract to spend tokens
2. **Bridge**: Bridges tokens from L1 to L2 (or vice versa)

### Placeholders

The template uses these placeholders that get substituted:

- `{ChainID}`: Chain ID from config
- `{TokenHolderSafe}`: Safe address that holds tokens
- `{TokenContract}`: Token contract address
- `{TokenSupply}`: Amount of tokens to bridge
- `{BridgeContract}`: Bridge contract address

## Output

The script generates a JSON file in the `out/` directory that is compatible with Safe's transaction builder interface. The file can be imported into Safe for execution.

## Error Handling

The script validates:
- All required addresses are valid Ethereum addresses
- Chain IDs are positive numbers
- Token supply amounts are greater than zero
- Config files exist and are valid JSON
- All required values are present

## Dependencies

- `commander`: Command line argument parsing
- `dotenv`: Environment variable loading

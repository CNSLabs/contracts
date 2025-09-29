# CNS Contract Prototyping

A Foundry-based smart contract development project for CNS (Contract Name Service) prototyping.

## Overview

This project uses [Foundry](https://foundry.paradigm.xyz), a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools)
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network
- **Chisel**: Fast, utilitarian, and verbose solidity REPL

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Git

## Pre-commit Hook Setup

This project includes a pre-commit hook that ensures all Solidity code is properly formatted before commits. The hook runs `forge fmt --check` and blocks commits if formatting issues are found.

### Automatic Setup

Run the setup script to install the pre-commit hook:

```bash
./setup-pre-commit.sh
```

### Manual Setup

If you prefer to set up the hook manually:

1. Copy the pre-commit hook to your git hooks directory:
   ```bash
   cp .git/hooks/pre-commit .git/hooks/pre-commit.backup  # backup existing if any
   ```

2. The hook is already installed in `.git/hooks/pre-commit` and will automatically run before each commit.

### How It Works

- **Before each commit**: The hook runs `forge fmt --check`
- **If formatting issues are found**: The commit is blocked with helpful error messages
- **To fix issues**: Run `forge fmt` to automatically format your code
- **To check without fixing**: Run `forge fmt --check` to see what needs to be fixed

### Bypassing the Hook (Not Recommended)

If you absolutely need to bypass the hook for a specific commit:

```bash
git commit --no-verify -m "your commit message"
```

**Note**: This should only be used in exceptional circumstances, as it defeats the purpose of maintaining code quality.

## Installation

1. Clone this repository:
```bash
git clone <repository-url>
cd cns-contract-prototyping
```

2. Install dependencies:
```bash
forge install
```

## Quick Start

### Build

```bash
forge build
```

### Test

```bash
# Run all tests
forge test

# Run tests with gas reporting
forge test --gas-report

# Run tests with verbosity
forge test -vvv

# Run specific test
forge test --match-test testIncrement
```

### Format Code

```bash
forge fmt
```

### Gas Snapshots

```bash
# Create gas snapshot
forge snapshot

# Compare with previous snapshot
forge snapshot --diff
```

### Local Development

Start a local Anvil node:

```bash
anvil
```

Deploy to local network:

```bash
forge script script/Counter.s.sol:CounterScript --rpc-url http://localhost:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast
```

### Cast Commands

```bash
# Get block number
cast block-number

# Get balance
cast balance <address>

# Call contract function
cast call <contract_address> "function_name(uint256)" <value> --rpc-url <rpc_url>

# Send transaction
cast send <contract_address> "function_name(uint256)" <value> --private-key <private_key> --rpc-url <rpc_url>
```

## Linea Deployment Checklist

- **Pin dependencies**: Vendor `src/linea/BridgedToken.sol` and `CustomBridgedToken.sol` from Linea commit `c7bc6313a6309d31ac532ce0801d1c3ad3426842`. Record this hash in deployment notes.
- **Bridge addresses**: Supply the correct Linea TokenBridge (L2) address through `LINEA_L2_BRIDGE` env var during scripts. Refer to ConsenSys docs or deployment manifests (e.g., `linea-deployment-manifests`) for network-specific values (Mainnet vs Sepolia).
- **Initializer params**: When calling `CNSTokenL2.initialize`, provide admin Safe, TokenBridge address, linked L1 token, L2 metadata (`name`, `symbol`, `decimals`). Ensure non-zero addresses to satisfy runtime guards.
- **Role separation**:
  - `DEFAULT_ADMIN_ROLE` / `UPGRADER_ROLE`: governance Safe (timelock if possible).
  - `PAUSER_ROLE`: fast-response Safe for incident handling.
  - `ALLOWLIST_ADMIN_ROLE`: operations Safe controlling transfer allowlist.
- **Allowlist defaults**: Implementation auto-allowlists itself, the bridge, and admin. Add additional operational addresses before enabling user transfers.
- **Linking workflow**: Coordinate with Linea bridge operators to link the L1 canonical token to the new L2 implementation. Capture approval transaction hashes for the deployment report.
- **Operational tests**:
  - On Linea Sepolia, simulate deposit (L1 escrow → L2 mint) and withdrawal (L2 burn → L1 release).
  - Verify allowlist enforcement by attempting transfers between non-allowlisted accounts (should revert) and allowlisted accounts (should succeed when unpaused).
  - Exercise pause/unpause and verify the bridge can still mint/burn.
- **Upgrades**: Test a dummy implementation upgrade via Foundry to confirm `_authorizeUpgrade` role gating. Maintain a change log for auditors.
- **Monitoring & runbooks**: Document emergency procedures for pausing, allowlist updates, and upgrade approvals. Consider on-chain monitoring for bridge-exclusive mint/burn events.

## Project Structure

```
├── src/                 # Smart contracts
├── test/                # Test files
├── script/              # Deployment scripts
├── lib/                 # Dependencies
├── foundry.toml         # Foundry configuration
└── README.md           # This file
```

## Configuration

The project is configured with:

- Solidity version: 0.8.25
- Optimizer enabled with 200 runs
- Gas reporting enabled
- Fuzz testing with 256 runs
- Invariant testing configured

See `foundry.toml` for detailed configuration options.

## Documentation

- [Foundry Book](https://book.getfoundry.sh/)
- [Foundry GitHub](https://github.com/foundry-rs/foundry)
- [Foundry Documentation](https://foundry.paradigm.xyz)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Run `forge test` to ensure all tests pass
6. Run `forge fmt` to format code
7. Submit a pull request

## License

This project is licensed under the MIT License.

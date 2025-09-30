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

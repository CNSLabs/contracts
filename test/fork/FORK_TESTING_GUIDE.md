# Production-Like Fork Testing Guide

This guide explains how to test your upgradeable contracts on production-like state using Anvil forking, Safe multisig impersonation, and timelock bypass techniques.

## Overview

The fork testing infrastructure allows you to:
- Fork mainnet/testnet at a specific block
- Impersonate Safe multisig to bypass signature requirements
- Bypass timelock delays using `anvil_setNextBlockTimestamp`
- Test complete upgrade flows on production-like state
- Verify state preservation and new functionality

## Setup

### 1. Environment Configuration

Create or update your `.env` file with the required RPC URLs:

```bash
# RPC URLs for forking
LINEA_MAINNET_RPC_URL=https://linea-mainnet.infura.io/v3/YOUR_KEY
LINEA_SEPOLIA_RPC_URL=https://linea-sepolia.infura.io/v3/YOUR_KEY

# Test environment (dev/production)
ENV=dev

# Optional: Specific fork block number
FORK_BLOCK_NUMBER=12345678

```

### 2. Configuration Files

Update your configuration files (`config/dev.json`, `config/production.json`) with production addresses:

```json
{
  "env": "production",
  "l2": {
    "proxy": "0x...", // Token L2 Proxy address
    "timelock": {
      "addr": "0x...", // Timelock Controller address
      "minDelay": 172800
    },
    "roles": {
      "admin": "0x..." // Safe multisig address
    }
  }
}
```

## Usage

### Running Fork Tests

```bash
# Run all fork tests - Foundry handles forking automatically
forge test --match-path "test/fork/*" -vv

# Run specific test
forge test --match-test "testCompleteUpgradeFlow" -vv

# Run with specific environment
ENV=production forge test --match-path "test/fork/*" -vv
```

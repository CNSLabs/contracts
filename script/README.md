# Deployment Scripts

This directory contains deployment and utility scripts for the SHO token L1 contract.

## Quick Start

All scripts should inherit from `BaseScript.sol` to avoid code duplication and get access to shared utilities.

```solidity
import "./BaseScript.sol";

contract MyScript is BaseScript {
    function run() external {
        // Your script logic here
    }
}
```

## Available Scripts

### Deployment Scripts

- **`1_DeployShoTokenL1.s.sol`** - Deploy SHO Token on L1 (Ethereum) as upgradeable UUPS contract
  ```bash
  # Deploy to Sepolia testnet
  forge script script/1_DeployShoTokenL1.s.sol:DeployShoTokenL1 \
    --rpc-url sepolia \
    --broadcast \
    --verify
  
  # Deploy to Mainnet
  ENV=production forge script script/1_DeployShoTokenL1.s.sol:DeployShoTokenL1 \
    --rpc-url mainnet \
    --broadcast \
    --verify \
    --slow
  ```
  
  > 💡 **Note:** This script deploys:
  > 1. Implementation contract (ShoTokenL1)
  > 2. ERC1967Proxy pointing to the implementation
  > 3. Initializes the proxy with all roles and mints initial supply
  > 
  > The proxy address is the token address users interact with. The implementation can be upgraded later by authorized roles.

## BaseScript Utilities

### Network Detection

```solidity
// Get human-readable network name
string memory network = _getNetworkName(block.chainid);

// Check network type
bool mainnet = _isMainnet();      // true for Ethereum/Linea mainnet
bool testnet = _isTestnet();      // true for Sepolia/Linea Sepolia
bool local = _isLocalNetwork();   // true for Anvil/Hardhat

// Get verification chain parameter
string memory chain = _getChainParam(block.chainid); // e.g., "--chain linea-sepolia"
```

### Chain ID Constants

```solidity
ETHEREUM_MAINNET    // 1
ETHEREUM_SEPOLIA    // 11155111
LINEA_MAINNET       // 59144
LINEA_SEPOLIA       // 59141
ANVIL               // 31337
HARDHAT             // 1337
```

### Logging Helpers

```solidity
// Log deployment header with network info
_logDeploymentHeader("Deploying MyContract");

// Log verification command
_logVerificationCommand(
    address(myContract),
    "src/MyContract.sol:MyContract"
);

// Log verification with constructor args
_logVerificationCommandWithArgs(
    address(myContract),
    "src/MyContract.sol:MyContract",
    abi.encode(arg1, arg2)
);
```

### Validation Helpers

```solidity
// Validate address is not zero
_requireNonZeroAddress(ownerAddress, "OWNER");

// Validate address is a contract
_requireContract(proxyAddress, "PROXY");

// Require explicit mainnet confirmation
_requireMainnetConfirmation(); // Set MAINNET_DEPLOYMENT_ALLOWED=true in .env
```

### Environment Helpers

```solidity
// Get deployer info
(uint256 privateKey, address deployerAddress) = _getDeployer();
```

## Example: Creating a New Deployment Script

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./BaseScript.sol";
import "../src/MyContract.sol";

/**
 * @title DeployMyContract
 * @notice Deploys MyContract to any EVM network
 * 
 * Usage:
 *   forge script script/DeployMyContract.s.sol:DeployMyContract \
 *     --rpc-url <network> \
 *     --broadcast \
 *     --verify
 */
contract DeployMyContract is BaseScript {
    function run() external {
        // Get deployer credentials
        (uint256 pk, address deployer) = _getDeployer();
        
        // Get and validate constructor arguments
        address owner = vm.envAddress("OWNER");
        _requireNonZeroAddress(owner, "OWNER");
        
        // Log deployment info
        _logDeploymentHeader("Deploying MyContract");
        console.log("Owner:", owner);
        console.log("Deployer:", deployer);
        
        // Safety check for mainnet
        _requireMainnetConfirmation();
        
        // Deploy
        vm.startBroadcast(pk);
        MyContract myContract = new MyContract(owner);
        vm.stopBroadcast();
        
        // Log results
        console.log("\n=== Deployment Complete ===");
        console.log("MyContract:", address(myContract));
        
        // Log verification command
        _logVerificationCommand(
            address(myContract),
            "src/MyContract.sol:MyContract"
        );
    }
}
```

## Deployment Workflow

### Deploy L1 Token

1. **Set Environment Variables**
   ```bash
   # Required
   export PRIVATE_KEY=0xYourPrivateKey
   export ENV=dev  # or production, alpha, alpha2
   
   # Optional overrides (otherwise uses config/<ENV>.json)
   export SHO_DEFAULT_ADMIN=0xYourMultisigAddress
   export SHO_UPGRADER=0xUpgraderAddress
   export SHO_PAUSER=0xPauserAddress
   export SHO_ALLOWLIST_ADMIN=0xAllowlistAdminAddress
   export SHO_INITIAL_RECIPIENT=0xRecipientAddress
   export L1_TOKEN_NAME="SHO Token"
   export L1_TOKEN_SYMBOL="SHO"
   
   # For mainnet deployments
   export MAINNET_DEPLOYMENT_ALLOWED=true
   ```

2. **Deploy to Testnet**
   ```bash
   # Deploy to Sepolia
   forge script script/1_DeployShoTokenL1.s.sol:DeployShoTokenL1 \
     --rpc-url sepolia \
     --broadcast \
     --verify
   ```

3. **Verify Deployment**
   ```bash
   # Check token info
   cast call <PROXY_ADDRESS> "name()(string)" --rpc-url sepolia
   cast call <PROXY_ADDRESS> "symbol()(string)" --rpc-url sepolia
   cast call <PROXY_ADDRESS> "totalSupply()(uint256)" --rpc-url sepolia
   cast call <PROXY_ADDRESS> "balanceOf(address)(uint256)" <RECIPIENT_ADDRESS> --rpc-url sepolia
   ```

4. **Deploy to Mainnet**
   ```bash
   # Make sure MAINNET_DEPLOYMENT_ALLOWED=true
   ENV=production forge script script/1_DeployShoTokenL1.s.sol:DeployShoTokenL1 \
     --rpc-url mainnet \
     --broadcast \
     --verify \
     --slow
   ```

### Post-Deployment

After deployment, you'll have:
- **Implementation Contract**: The upgradeable logic contract
- **Proxy Contract**: The ERC1967Proxy that users interact with (this is the token address)
- **Initial Supply**: 1B tokens minted to the initial recipient
- **Allowlist**: Enabled by default, with contract, admin, and initial recipient allowlisted

To upgrade the contract later:
1. Deploy a new implementation contract
2. Call `upgradeTo(newImplementation)` from an address with `UPGRADER_ROLE`

## Environment Variables

Required variables in `.env`:

```bash
# Required for all scripts
PRIVATE_KEY=0x...                     # Deployer private key
ENV=dev                                # Environment: dev, alpha, alpha2, production

# Optional: Override config values (otherwise uses config/<ENV>.json)
SHO_DEFAULT_ADMIN=0x...               # DEFAULT_ADMIN_ROLE address
SHO_UPGRADER=0x...                    # UPGRADER_ROLE address
SHO_PAUSER=0x...                      # PAUSER_ROLE address
SHO_ALLOWLIST_ADMIN=0x...             # ALLOWLIST_ADMIN_ROLE address
SHO_INITIAL_RECIPIENT=0x...           # Receives initial 1B token supply
L1_TOKEN_NAME="SHO Token"             # Token name
L1_TOKEN_SYMBOL="SHO"                 # Token symbol

# Required for mainnet deployments
MAINNET_DEPLOYMENT_ALLOWED=true

# Network RPC URLs (used by foundry.toml aliases)
ETH_MAINNET_RPC_URL=https://...
ETH_SEPOLIA_RPC_URL=https://...

# Verification API keys
ETHERSCAN_API_KEY=...
```

### Config Files

Configuration is loaded from `config/<ENV>.json` files. The structure should include:

```json
{
  "l1": {
    "name": "SHO Token",
    "symbol": "SHO",
    "roles": {
      "admin": "0x...",
      "upgrader": "0x...",
      "pauser": "0x...",
      "allowlistAdmin": "0x..."
    }
  }
}
```

Environment variables take precedence over config file values.

## Network Aliases

Defined in `foundry.toml`:

```bash
# Use short names instead of full URLs
forge script ... --rpc-url mainnet --broadcast
forge script ... --rpc-url sepolia --broadcast
forge script ... --rpc-url local --broadcast
```

## Testing Scripts Locally

```bash
# Start local Anvil chain
anvil

# In another terminal, run script against local chain
forge script script/YourScript.s.sol:YourScript \
  --rpc-url http://localhost:8545 \
  --broadcast
```

## Best Practices

1. ✅ **Always inherit from BaseScript** instead of Script
2. ✅ **Use `--rpc-url` parameter** for network selection
3. ✅ **Validate all inputs** with helper functions
4. ✅ **Test locally first** with Anvil before testnet/mainnet
5. ✅ **Log everything important** for debugging
6. ✅ **Add usage docs** in contract comments
7. ✅ **Use mainnet confirmation** for production deployments

## Contract Details

### ShoTokenL1 Features

- **Upgradeable**: Uses UUPS (Universal Upgradeable Proxy Standard) pattern
- **ERC20Permit**: Supports gasless approvals via EIP-2612
- **Allowlist Control**: Only allowlisted addresses can transfer tokens
- **Pausable**: Can be paused by authorized roles in emergencies
- **Role-Based Access Control**: Separate roles for admin, upgrader, pauser, and allowlist admin
- **Initial Supply**: 1 billion tokens minted to initial recipient on deployment

### Upgrade Process

The contract is upgradeable via UUPS pattern:

1. Deploy new implementation contract
2. Call `upgradeTo(newImplementation)` from address with `UPGRADER_ROLE`
3. Storage is preserved in the proxy
4. New logic takes effect immediately

> ⚠️ **Important**: Always verify storage layout compatibility before upgrading!

## See Also

- [`BaseScript.sol`](./BaseScript.sol) - Source code for base script utilities
- [`ConfigLoader.sol`](./ConfigLoader.sol) - Configuration loading utilities
- [Foundry Book - Scripts](https://book.getfoundry.sh/tutorials/solidity-scripting) - Official Foundry scripting guide
- [OpenZeppelin UUPS Docs](https://docs.openzeppelin.com/contracts/4.x/api/proxy#UUPSUpgradeable) - UUPS upgradeable pattern documentation


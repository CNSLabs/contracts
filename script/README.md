# Deployment Scripts

This directory contains deployment and utility scripts for the CNS token contracts.

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

- **`1_DeployShoTokenL1.s.sol`** - Deploy CNS Token on L1 (Ethereum)
  ```bash
  # New: zero-arg run() with inferred config
  # Select env via ENV (default: dev)
  forge script script/1_DeployShoTokenL1.s.sol:DeployShoTokenL1 \
    --rpc-url sepolia \
    --broadcast --verify

  # Sepolia testnet
  forge script script/1_DeployShoTokenL1.s.sol:DeployShoTokenL1 \
    --rpc-url sepolia \
    --broadcast \
    --verify
  
  # Mainnet
  forge script script/1_DeployShoTokenL1.s.sol:DeployShoTokenL1 \
    --rpc-url mainnet \
    --broadcast \
    --verify \
    --slow
  ```

- **`2_DeployShoTokenL2.s.sol`** - Deploy CNS Token on L2 (Linea) with proxy
  ```bash
  # New: zero-arg run() with inferred config
  # Select env via ENV (default: dev)
  forge script script/2_DeployShoTokenL2.s.sol:DeployShoTokenL2 \
    --rpc-url linea-sepolia \
    --broadcast --verify

  # Linea Sepolia testnet
  forge script script/2_DeployShoTokenL2.s.sol:DeployShoTokenL2 \
    --rpc-url linea-sepolia \
    --broadcast \
    --verify
  
  # Linea Mainnet
  forge script script/2_DeployShoTokenL2.s.sol:DeployShoTokenL2 \
    --rpc-url linea \
    --broadcast \
    --verify \
    --slow
  ```
  
  > 💡 **Note:** Ensure `CNS_TOKEN_L1` is set in your `.env` file before deployment.
  > If you encounter "Replacement transaction underpriced" errors, clear the broadcast cache:
  > ```bash
  > rm -rf broadcast/2_DeployShoTokenL2.s.sol/59141/
  > ```

### Upgrade Scripts

- **`3_UpgradeShoTokenL2ToV2_Schedule.s.sol`** - Upgrade L2 token from V1 to V2 (adds voting)
  ```bash
  # Testnet
  forge script script/3_UpgradeShoTokenL2ToV2_Schedule.s.sol:UpgradeShoTokenL2ToV2_Schedule \
    --rpc-url linea-sepolia \
    --broadcast \
    --verify
  
  # Local testing
  forge script script/3_UpgradeShoTokenL2ToV2_Schedule.s.sol:UpgradeShoTokenL2ToV2_Schedule \
    --rpc-url http://localhost:8545 \
    --broadcast
  ```

- **`4_CreateHedgeyInvestorLockup.s.sol`** - Create Hedgey investor lockup plan
  ```bash
  # Linea Sepolia testnet
  forge script script/4_CreateHedgeyInvestorLockup.s.sol:CreateHedgeyInvestorLockup \
    --rpc-url linea-sepolia \
    --broadcast
  ```
  
  > 💡 **Note:** Requires `HEDGEY_INVESTOR_LOCKUP` and other Hedgey parameters in `.env`

### Utility Scripts

- **`DemoV2Features.s.sol`** - Demo script showing V2 voting features
  ```bash
  forge script script/DemoV2Features.s.sol:DemoV2Features --rpc-url linea-sepolia
  ```

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

### Full Deployment (L1 + L2)

1. **Deploy L1 Token on Ethereum**
   ```bash
   # Set environment variables
   export CNS_OWNER=0xYourMultisigAddress
   
   # Deploy to Sepolia
   forge script script/1_DeployShoTokenL1.s.sol:DeployShoTokenL1 \
     --rpc-url sepolia \
     --broadcast \
     --verify
   
   # Save the deployed L1 token address
   export CNS_TOKEN_L1=0xDeployedL1Address
   ```

2. **Deploy L2 Token on Linea**
   ```bash
   # Make sure CNS_TOKEN_L1 is set from step 1 (or in .env)
   # Bridge address should already be in your .env file
   
   # Deploy to Linea Sepolia
   forge script script/2_DeployShoTokenL2.s.sol:DeployShoTokenL2 \
     --rpc-url linea-sepolia \
     --broadcast \
     --verify
   
   # Save the deployed L2 proxy address to .env
   echo "CNS_TOKEN_L2_PROXY=<deployed_address>" >> .env
   ```

3. **Test the Deployment**
   ```bash
   # Add addresses to allowlist
   cast send $CNS_TOKEN_L2_PROXY \
     "setAllowlist(address,bool)" \
     0xUserAddress \
     true \
     --private-key $PRIVATE_KEY \
     --rpc-url linea-sepolia
   
   # Bridge some tokens from L1 to L2 using Linea bridge UI
   ```

4. **Upgrade to V2 (Optional)**
   ```bash
   # Upgrade to add voting capabilities
   forge script script/3_UpgradeShoTokenL2ToV2_Schedule.s.sol:UpgradeShoTokenL2ToV2_Schedule \
     --rpc-url linea-sepolia \
     --broadcast \
     --verify
   ```

## Environment Variables

Required variables in `.env`:

```bash
# Required for all scripts
PRIVATE_KEY=0x...
CNS_OWNER=0x...

# Required for L2 deployment
CNS_TOKEN_L1=0x...                    # L1 token address (deploy L1 first)
LINEA_L2_BRIDGE=0x...                 # Linea bridge address for your network

# Required for upgrade scripts
CNS_TOKEN_L2_PROXY=0x...              # L2 proxy address (after L2 deployment)

# Required for mainnet deployments
MAINNET_DEPLOYMENT_ALLOWED=true

# Network RPC URLs (used by foundry.toml aliases)
ETH_MAINNET_RPC_URL=https://...
ETH_SEPOLIA_RPC_URL=https://...
LINEA_MAINNET_RPC_URL=https://...
LINEA_SEPOLIA_RPC_URL=https://...

# Verification API keys
ETHERSCAN_API_KEY=...
LINEA_ETHERSCAN_API_KEY=...
```

## Network Aliases

Defined in `foundry.toml`:

```bash
# Use short names instead of full URLs
forge script ... --rpc-url mainnet --broadcast
forge script ... --rpc-url sepolia --broadcast
forge script ... --rpc-url linea --broadcast
forge script ... --rpc-url linea-sepolia --broadcast
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

## See Also

- [`DEPLOYMENT_BEST_PRACTICES.md`](../DEPLOYMENT_BEST_PRACTICES.md) - Comprehensive deployment guide
- [`BaseScript.sol`](./BaseScript.sol) - Source code for base script utilities
- [Foundry Book - Scripts](https://book.getfoundry.sh/tutorials/solidity-scripting) - Official Foundry scripting guide


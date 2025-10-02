# Deployment Scripts

Deployment and utility scripts for CNS token contracts.

## Scripts Overview

### Deployment
- **`1_DeployCNSTokenL1.s.sol`** - Deploy CNS token on Ethereum L1
- **`2_DeployCNSTokenL2.s.sol`** - Deploy CNS token on Linea L2 (with proxy)
- **`3_UpgradeCNSTokenL2ToV2.s.sol`** - Upgrade L2 token to V2 (adds governance)
- **`DeployCNSContracts.s.sol`** - Legacy multi-chain deployment

### Utilities
- **`BaseScript.sol`** - Shared helpers for all scripts (inherit from this)

## Quick Start

```bash
# Deploy L1 (Sepolia)
forge script script/1_DeployCNSTokenL1.s.sol:DeployCNSTokenL1 \
  --rpc-url sepolia \
  --broadcast \
  --verify

# Deploy L2 (Linea Sepolia) - after setting CNS_TOKEN_L1
forge script script/2_DeployCNSTokenL2.s.sol:DeployCNSTokenL2 \
  --rpc-url linea_sepolia \
  --broadcast \
  --verify

# Upgrade to V2 - after setting CNS_TOKEN_L2_PROXY
forge script script/3_UpgradeCNSTokenL2ToV2.s.sol:UpgradeCNSTokenL2ToV2 \
  --rpc-url linea_sepolia \
  --broadcast \
  --verify
```

## BaseScript Utilities

All scripts inherit from `BaseScript.sol` for shared functionality:

### Network Detection

```solidity
_getNetworkName(block.chainid)     // "Ethereum Sepolia"
_isMainnet()                        // true if Ethereum/Linea mainnet
_isTestnet()                        // true if Sepolia/Linea Sepolia
_isLocalNetwork()                   // true if Anvil/Hardhat
_getChainParam(block.chainid)       // "--chain sepolia"
```

### Logging

```solidity
_logDeploymentHeader("Deploying MyContract")
_logVerificationCommand(contractAddress, "src/MyContract.sol:MyContract")
_logVerificationCommandWithArgs(address, path, constructorArgs)
```

### Validation

```solidity
_requireNonZeroAddress(address, "NAME")
_requireContract(address, "NAME")
_requireMainnetConfirmation()  // Requires MAINNET_DEPLOYMENT_ALLOWED=true
```

### Environment

```solidity
(uint256 privateKey, address deployer) = _getDeployer()
```

## Full Deployment Workflow

### 1. Deploy L1 Token

```bash
# Set environment
export CNS_OWNER=0xYourMultisigAddress

# Deploy to Sepolia
forge script script/1_DeployCNSTokenL1.s.sol:DeployCNSTokenL1 \
  --rpc-url sepolia \
  --broadcast \
  --verify

# Save deployed address
export CNS_TOKEN_L1=0x...
```

### 2. Deploy L2 Token

```bash
# Set L2 bridge address (network-specific)
export LINEA_L2_BRIDGE=0x93DcAdf238932e6e6a85852caC89cBd71798F463  # Sepolia

# Deploy to Linea Sepolia
forge script script/2_DeployCNSTokenL2.s.sol:DeployCNSTokenL2 \
  --rpc-url linea_sepolia \
  --broadcast \
  --verify

# Save proxy address
export CNS_TOKEN_L2_PROXY=0x...
```

### 3. Test Deployment

```bash
# Add addresses to allowlist
cast send $CNS_TOKEN_L2_PROXY \
  "setAllowlist(address,bool)" 0xUserAddress true \
  --private-key $PRIVATE_KEY \
  --rpc-url linea_sepolia

# Bridge tokens using Linea bridge UI
```

### 4. Upgrade to V2 (Optional)

```bash
forge script script/3_UpgradeCNSTokenL2ToV2.s.sol:UpgradeCNSTokenL2ToV2 \
  --rpc-url linea_sepolia \
  --broadcast \
  --verify
```

## Environment Variables

Required in `.env`:

```bash
# Always required
PRIVATE_KEY=0x...
CNS_OWNER=0x...

# For L2 deployment
CNS_TOKEN_L1=0x...                    # From L1 deployment
LINEA_L2_BRIDGE=0x...                 # Sepolia: 0x93Dc... | Mainnet: 0xd19d...

# For upgrades
CNS_TOKEN_L2_PROXY=0x...              # From L2 deployment

# For mainnet
MAINNET_DEPLOYMENT_ALLOWED=true

# RPC URLs (optional, can use foundry.toml aliases)
ETH_SEPOLIA_RPC_URL=https://...
LINEA_SEPOLIA_RPC_URL=https://...

# For verification
ETHERSCAN_API_KEY=...
LINEA_ETHERSCAN_API_KEY=...
```

## Network Aliases

Defined in `foundry.toml`:

```bash
--rpc-url mainnet          # Ethereum mainnet
--rpc-url sepolia          # Ethereum Sepolia
--rpc-url linea            # Linea mainnet
--rpc-url linea_sepolia    # Linea Sepolia
--rpc-url local            # http://localhost:8545
```

## Creating New Scripts

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./BaseScript.sol";
import "../src/MyContract.sol";

contract DeployMyContract is BaseScript {
    function run() external {
        (uint256 pk, address deployer) = _getDeployer();
        address owner = vm.envAddress("OWNER");
        _requireNonZeroAddress(owner, "OWNER");
        
        _logDeploymentHeader("Deploying MyContract");
        _requireMainnetConfirmation();
        
        vm.startBroadcast(pk);
        MyContract myContract = new MyContract(owner);
        vm.stopBroadcast();
        
        console.log("MyContract:", address(myContract));
        _logVerificationCommand(address(myContract), "src/MyContract.sol:MyContract");
    }
}
```

## Best Practices

- ✅ Always inherit from `BaseScript`
- ✅ Validate all inputs with `_require*` helpers
- ✅ Test locally with Anvil first
- ✅ Use network aliases from `foundry.toml`
- ✅ Log important info for debugging
- ✅ Enable mainnet confirmation for production

## See Also

- [LOCAL_TESTING_GUIDE.md](../LOCAL_TESTING_GUIDE.md) - Local testing with Anvil
- [Foundry Book - Scripts](https://book.getfoundry.sh/tutorials/solidity-scripting)

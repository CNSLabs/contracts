# Foundry Deployment Script Best Practices

This guide explains best practices for writing flexible, maintainable deployment scripts in Foundry.

## Table of Contents

- [Network Selection](#network-selection)
- [Script Structure](#script-structure)
- [Testing Scripts Locally](#testing-scripts-locally)
- [Multi-Chain Deployments](#multi-chain-deployments)
- [Security Best Practices](#security-best-practices)

## Network Selection

### ✅ DO: Use `--rpc-url` CLI Parameter

**Your scripts should be network-agnostic** and accept the RPC URL via command line:

```solidity
contract DeployScript is Script {
    function run() external {
        // Script works on whatever network you specify via CLI
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Detect network using block.chainid
        console.log("Deploying to:", _getNetworkName(block.chainid));
        
        vm.startBroadcast(deployerPrivateKey);
        // Deploy contracts...
        vm.stopBroadcast();
    }
}
```

**Usage:**

```bash
# Testnet
forge script script/Deploy.s.sol --rpc-url https://rpc.sepolia.linea.build --broadcast

# Local dev
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast

# Using network aliases (see below)
forge script script/Deploy.s.sol --rpc-url linea_sepolia --broadcast
```

### ✅ DO: Configure Network Aliases in `foundry.toml`

Define common networks once, use everywhere:

```toml
[rpc_endpoints]
mainnet = "${ETH_MAINNET_RPC_URL}"
sepolia = "${ETH_SEPOLIA_RPC_URL}"
linea = "${LINEA_MAINNET_RPC_URL}"
linea_sepolia = "${LINEA_SEPOLIA_RPC_URL}"
local = "http://localhost:8545"

[etherscan]
linea = { key = "${LINEA_ETHERSCAN_API_KEY}", url = "https://api.lineascan.build/api" }
linea_sepolia = { key = "${LINEA_ETHERSCAN_API_KEY}", url = "https://api-sepolia.lineascan.build/api" }
```

Then use short names:

```bash
forge script script/Deploy.s.sol --rpc-url linea_sepolia --broadcast --verify
```

### ❌ DON'T: Hardcode RPC URLs in Scripts

```solidity
// ❌ BAD: Hardcoded network
string memory rpcUrl = "https://rpc.sepolia.linea.build";
uint256 fork = vm.createFork(rpcUrl);
vm.selectFork(fork);
```

This prevents deploying to local dev chains or other networks.

### ❌ DON'T: Use `createFork`/`selectFork` in Deployment Scripts

**These are for testing, not deployment:**

```solidity
// ❌ BAD: Fork pattern (use in tests, not deployment)
uint256 fork = vm.createFork(rpcUrl);
vm.selectFork(fork);
```

**Why?** `createFork` creates a local simulation of a network. For actual deployments, you want to deploy directly to the network specified via `--rpc-url`.

**When to use forks:** In tests or multi-chain simulation scripts only.

## Script Structure

### Use BaseScript for Shared Utilities

**All deployment scripts should inherit from `BaseScript` instead of `Script`:**

```solidity
// ✅ GOOD: Use BaseScript
import "./BaseScript.sol";

contract MyDeployScript is BaseScript {
    function run() external {
        // Automatically get deployer info
        (uint256 pk, address deployer) = _getDeployer();
        
        // Use built-in network detection
        _logDeploymentHeader("Deploying MyContract");
        
        // Use validation helpers
        address owner = vm.envAddress("OWNER");
        _requireNonZeroAddress(owner, "OWNER");
        
        // Check for mainnet deployment
        _requireMainnetConfirmation();
        
        vm.startBroadcast(pk);
        MyContract myContract = new MyContract(owner);
        vm.stopBroadcast();
        
        // Use built-in verification helper
        _logVerificationCommand(address(myContract), "src/MyContract.sol:MyContract");
    }
}
```

**BaseScript provides:**
- ✅ Chain ID constants (LINEA_MAINNET, LINEA_SEPOLIA, etc.)
- ✅ Network detection helpers (`_getNetworkName()`, `_isMainnet()`, etc.)
- ✅ Verification command generation (`_logVerificationCommand()`)
- ✅ Deployment logging (`_logDeploymentHeader()`)
- ✅ Validation helpers (`_requireNonZeroAddress()`, `_requireContract()`)
- ✅ Mainnet safety checks (`_requireMainnetConfirmation()`)

This avoids code duplication across multiple scripts!

### Detect Network Automatically

Use BaseScript's built-in helpers or `block.chainid` to detect which network you're on:

```solidity
contract DeployScript is Script {
    // Chain IDs
    uint256 constant LINEA_MAINNET = 59144;
    uint256 constant LINEA_SEPOLIA = 59141;
    uint256 constant LOCAL = 31337; // Anvil
    
    function run() external {
        string memory network = _getNetworkName(block.chainid);
        console.log("Deploying to:", network);
        
        // Network-specific logic if needed
        if (block.chainid == LINEA_MAINNET) {
            // Mainnet-specific checks
            require(someCondition, "Safety check for mainnet");
        }
        
        // Deploy...
    }
    
    function _getNetworkName(uint256 chainId) internal pure returns (string memory) {
        if (chainId == LINEA_MAINNET) return "Linea Mainnet";
        if (chainId == LINEA_SEPOLIA) return "Linea Sepolia";
        if (chainId == 31337) return "Local Anvil";
        if (chainId == 1337) return "Local Hardhat";
        return string.concat("Unknown (Chain ID: ", vm.toString(chainId), ")");
    }
}
```

### Include Usage Documentation

Add usage examples in your script comments:

```solidity
/**
 * @title DeployMyContract
 * @notice Deploys MyContract to any EVM network
 * 
 * Usage:
 *   # Testnet with verification
 *   forge script script/Deploy.s.sol:DeployMyContract \
 *     --rpc-url linea_sepolia \
 *     --broadcast \
 *     --verify
 * 
 *   # Local anvil
 *   forge script script/Deploy.s.sol:DeployMyContract \
 *     --rpc-url local \
 *     --broadcast
 * 
 *   # Custom RPC
 *   forge script script/Deploy.s.sol:DeployMyContract \
 *     --rpc-url https://custom-rpc.example.com \
 *     --broadcast
 */
contract DeployMyContract is Script {
    // ...
}
```

### Dynamic Verification Commands

Generate verification commands based on detected network:

```solidity
function _logVerificationCommand(address deployed) internal view {
    string memory chainParam = _getChainParam(block.chainid);
    
    if (bytes(chainParam).length > 0) {
        console.log("\nVerification command:");
        console.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(deployed),
                " src/MyContract.sol:MyContract ",
                chainParam,
                " --watch"
            )
        );
    } else {
        console.log("\nManual verification required");
        console.log("Contract address:", deployed);
    }
}

function _getChainParam(uint256 chainId) internal pure returns (string memory) {
    if (chainId == 59144) return "--chain linea";
    if (chainId == 59141) return "--chain linea-sepolia";
    if (chainId == 1) return "--chain mainnet";
    if (chainId == 11155111) return "--chain sepolia";
    return "";
}
```

## Testing Scripts Locally

### 1. Start a Local Anvil Chain

```bash
# Terminal 1: Start anvil
anvil

# Terminal 2: Deploy to local chain
forge script script/Deploy.s.sol \
  --rpc-url http://localhost:8545 \
  --broadcast \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

### 2. Fork a Mainnet for Testing

Test against real state without spending gas:

```bash
# Start anvil forked from Linea Sepolia
anvil --fork-url https://rpc.sepolia.linea.build

# In another terminal, deploy
forge script script/Deploy.s.sol \
  --rpc-url http://localhost:8545 \
  --broadcast
```

### 3. Use `forge script --dry-run`

Simulate without broadcasting:

```bash
forge script script/Deploy.s.sol \
  --rpc-url linea_sepolia
  # No --broadcast flag = dry run
```

## Multi-Chain Deployments

### Pattern for Cross-Chain Scripts

When you need to deploy to multiple chains in a single script (e.g., L1 token + L2 token):

```solidity
contract DeployMultiChain is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Get RPC URLs from environment
        string memory l1RpcUrl = vm.envString("ETH_SEPOLIA_RPC_URL");
        string memory l2RpcUrl = vm.envString("LINEA_SEPOLIA_RPC_URL");
        
        // Create forks for multi-chain deployment
        uint256 l1Fork = vm.createFork(l1RpcUrl);
        uint256 l2Fork = vm.createFork(l2RpcUrl);
        
        // Deploy on L1
        console.log("\n=== Deploying to L1 ===");
        vm.selectFork(l1Fork);
        address l1Token = _deployL1(deployerPrivateKey);
        
        // Deploy on L2
        console.log("\n=== Deploying to L2 ===");
        vm.selectFork(l2Fork);
        address l2Token = _deployL2(deployerPrivateKey, l1Token);
        
        _logSummary(l1Token, l2Token);
    }
    
    function _deployL1(uint256 pk) internal returns (address) {
        vm.startBroadcast(pk);
        MyL1Token token = new MyL1Token();
        vm.stopBroadcast();
        return address(token);
    }
    
    function _deployL2(uint256 pk, address l1Token) internal returns (address) {
        vm.startBroadcast(pk);
        MyL2Token token = new MyL2Token(l1Token);
        vm.stopBroadcast();
        return address(token);
    }
}
```

**Run it:**

```bash
forge script script/DeployMultiChain.s.sol:DeployMultiChain --broadcast
```

Note: Multi-chain scripts don't use `--rpc-url` because they manage multiple networks internally.

## Security Best Practices

### 1. Never Hardcode Private Keys

```solidity
// ❌ NEVER DO THIS
uint256 privateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

// ✅ Use environment variables
uint256 privateKey = vm.envUint("PRIVATE_KEY");
```

### 2. Add Safety Checks for Mainnet

```solidity
function run() external {
    // Require explicit confirmation for mainnet deployments
    if (block.chainid == 1 || block.chainid == 59144) {
        require(
            vm.envOr("DEPLOY_TO_MAINNET_CONFIRMED", false),
            "Set DEPLOY_TO_MAINNET_CONFIRMED=true to deploy to mainnet"
        );
    }
    
    // Rest of deployment...
}
```

### 3. Validate Constructor Arguments

```solidity
function run() external {
    address owner = vm.envAddress("OWNER");
    
    // Validate critical addresses
    require(owner != address(0), "Owner cannot be zero address");
    require(owner != msg.sender, "Owner should be multisig, not deployer");
    
    // Deploy with validated args
    vm.broadcast();
    new MyContract(owner);
}
```

### 4. Use Separate Keys for Testing

```bash
# .env.local (for local development)
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80  # Anvil default key

# .env.sepolia (for testnet)
PRIVATE_KEY=0x...  # Your testnet key

# .env.mainnet (for production)
PRIVATE_KEY=0x...  # Your mainnet key (store securely!)
```

Load different env files:

```bash
# Local
forge script script/Deploy.s.sol --rpc-url local --broadcast

# Testnet
source .env.sepolia && forge script script/Deploy.s.sol --rpc-url linea_sepolia --broadcast

# Mainnet (use hardware wallet in production!)
source .env.mainnet && forge script script/Deploy.s.sol --rpc-url linea --broadcast --verify
```

### 5. Log Everything Important

```solidity
function run() external {
    console.log("\n=== Deployment Configuration ===");
    console.log("Network:", _getNetworkName(block.chainid));
    console.log("Deployer:", deployer);
    console.log("Owner:", owner);
    console.log("Initial supply:", initialSupply);
    
    // ... deployment ...
    
    console.log("\n=== Deployment Complete ===");
    console.log("Token:", address(token));
    console.log("Block:", block.number);
    console.log("Gas used:", /* calculate gas */);
}
```

## Examples

### Simple Single-Chain Deployment

```bash
# Local
forge script script/3_UpgradeCNSTokenL2ToV2.s.sol:UpgradeCNSTokenL2ToV2 \
  --rpc-url local \
  --broadcast

# Testnet
forge script script/3_UpgradeCNSTokenL2ToV2.s.sol:UpgradeCNSTokenL2ToV2 \
  --rpc-url linea_sepolia \
  --broadcast \
  --verify

# Mainnet
forge script script/3_UpgradeCNSTokenL2ToV2.s.sol:UpgradeCNSTokenL2ToV2 \
  --rpc-url linea \
  --broadcast \
  --verify \
  --slow  # Use --slow for mainnet to avoid rate limits
```

### Multi-Chain Deployment

```bash
# Deploy to both L1 and L2
forge script script/DeployCNSContracts.s.sol:DeployCNSContracts \
  --broadcast \
  --multi
```

## Summary

✅ **DO:**
- Use `--rpc-url` CLI parameter for single-chain scripts
- Configure network aliases in `foundry.toml`
- Use `block.chainid` for network detection
- Test locally with Anvil before deploying to testnet/mainnet
- Add safety checks for mainnet deployments
- Log all important information

❌ **DON'T:**
- Hardcode RPC URLs in scripts
- Use `createFork`/`selectFork` in deployment scripts (only in tests)
- Commit private keys to version control
- Deploy to mainnet without thorough testing

Your scripts should be **flexible, secure, and easy to use across all environments**.


# Multisig Deployment Guide

This guide covers deploying CNSTokenL2 with proper role separation using Gnosis Safe multisig.

## Table of Contents

1. [Overview](#overview)
2. [Role Structure](#role-structure)
3. [Prerequisites](#prerequisites)
4. [Setup Gnosis Safe](#setup-gnosis-safe)
5. [Environment Configuration](#environment-configuration)
6. [Deployment Process](#deployment-process)
7. [Safe CLI Testing](#safe-cli-testing)
8. [Production Recommendations](#production-recommendations)

## Overview

The updated `CNSTokenL2` contract implements role separation to follow the principle of least privilege:

- **Multisig**: Controls critical functions (role management, upgrades)
- **Pauser**: Hot wallet for emergency response
- **Allowlist Admin**: Operational wallet for managing sender allowlist

The multisig also acts as a backup for operational roles, ensuring recovery capability if hot wallets are compromised.

## Role Structure

### Critical Roles (Multisig Only)

- **DEFAULT_ADMIN_ROLE** (`0x00`)
  - Can grant/revoke all roles
  - Most powerful role - must be protected
  
- **UPGRADER_ROLE**
  - Can upgrade contract implementation
  - Critical for contract evolution

### Operational Roles (Dedicated Addresses + Multisig Backup)

- **PAUSER_ROLE**
  - Can pause/unpause contract
  - Primary: Hot wallet for fast emergency response
  - Backup: Multisig
  
- **ALLOWLIST_ADMIN_ROLE**
  - Can manage sender allowlist
  - Primary: Operational hot wallet
  - Backup: Multisig

## Prerequisites

### Required Tools

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install Safe CLI (for testing)
pip install safe-cli

# Or using pipx (recommended)
pipx install safe-cli
```

### Network Access

- RPC endpoint for target network (Linea Mainnet, Linea Sepolia, etc.)
- Test ETH/Ether for gas fees
- Private keys for deployment and initial setup

## Setup Gnosis Safe

### Option 1: Using Safe Web Interface (Production)

1. **Go to Gnosis Safe App**
   - Mainnet: https://app.safe.global/
   - Testnet: https://app.safe.global/

2. **Create New Safe**
   - Click "Create new Safe"
   - Select Linea network
   - Add signer addresses
   - **Recommended**: 3-of-5 or 4-of-7 configuration
   - Deploy Safe

3. **Record Safe Address**
   ```bash
   export CNS_MULTISIG=0x...
   ```

### Option 2: Using Safe CLI (Development/Testing)

#### Install Safe CLI

```bash
# Using pip
pip install safe-cli

# Or using pipx (recommended for isolation)
pipx install safe-cli
```

#### Connect to Network

```bash
# For Linea Sepolia testnet
safe-cli linea_sepolia 0x0000000000000000000000000000000000000000

# For Linea Mainnet
safe-cli linea 0x0000000000000000000000000000000000000000
```

#### Create Safe via CLI

```bash
# Start Safe CLI
safe-cli

# Create Safe with 3-of-5 threshold
> create_safe <owner1> <owner2> <owner3> <owner4> <owner5> --threshold 3

# Record the Safe address
Safe created: 0x...
```

#### Alternative: Deploy Safe via Foundry Script

Create a script `script/DeployGnosisSafe.s.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

interface IGnosisSafeProxyFactory {
    function createProxyWithNonce(
        address _singleton,
        bytes memory initializer,
        uint256 saltNonce
    ) external returns (address);
}

interface IGnosisSafe {
    function setup(
        address[] calldata _owners,
        uint256 _threshold,
        address to,
        bytes calldata data,
        address fallbackHandler,
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver
    ) external;
}

contract DeployGnosisSafe is Script {
    // Linea Sepolia addresses (from Safe deployments)
    address constant SAFE_SINGLETON = 0x69f4D1788e39c87893C980c06EdF4b7f686e2938;
    address constant SAFE_PROXY_FACTORY = 0xC22834581EbC8527d974F8a1c97E1bEA4EF910BC;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        
        // Configure Safe owners
        address[] memory owners = new address[](5);
        owners[0] = vm.envAddress("SAFE_OWNER_1");
        owners[1] = vm.envAddress("SAFE_OWNER_2");
        owners[2] = vm.envAddress("SAFE_OWNER_3");
        owners[3] = vm.envAddress("SAFE_OWNER_4");
        owners[4] = vm.envAddress("SAFE_OWNER_5");
        
        uint256 threshold = 3; // 3-of-5
        
        console.log("Deploying Gnosis Safe with 3-of-5 threshold");
        console.log("Owners:");
        for (uint256 i = 0; i < owners.length; i++) {
            console.log("  ", owners[i]);
        }
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Prepare Safe setup data
        bytes memory setupData = abi.encodeWithSelector(
            IGnosisSafe.setup.selector,
            owners,
            threshold,
            address(0), // to
            "", // data
            address(0), // fallbackHandler
            address(0), // paymentToken
            0, // payment
            payable(address(0)) // paymentReceiver
        );
        
        // Deploy Safe proxy
        IGnosisSafeProxyFactory factory = IGnosisSafeProxyFactory(SAFE_PROXY_FACTORY);
        address safe = factory.createProxyWithNonce(
            SAFE_SINGLETON,
            setupData,
            block.timestamp
        );
        
        vm.stopBroadcast();
        
        console.log("\nSafe deployed at:", safe);
        console.log("\nAdd to .env:");
        console.log("CNS_MULTISIG=", safe);
    }
}
```

Deploy:

```bash
forge script script/DeployGnosisSafe.s.sol:DeployGnosisSafe \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

## Environment Configuration

Update your `.env` file with the role addresses:

```bash
# Network Configuration
RPC_URL=https://rpc.linea.build
CHAIN_ID=59144

# Deployment
DEPLOYER_PRIVATE_KEY=0x...

# Contract Addresses
CNS_TOKEN_L1=0x... # L1 token address
LINEA_L2_BRIDGE=0x... # Linea bridge address

# Role Addresses (NEW - Role Separation)
CNS_MULTISIG=0x...          # Gnosis Safe address (critical roles)
CNS_PAUSER=0x...            # Hot wallet for emergency pause (optional, defaults to multisig)
CNS_ALLOWLIST_ADMIN=0x...   # Operational wallet for allowlist (optional, defaults to multisig)

# Optional: Safe Owners (for deployment scripts)
SAFE_OWNER_1=0x...
SAFE_OWNER_2=0x...
SAFE_OWNER_3=0x...
SAFE_OWNER_4=0x...
SAFE_OWNER_5=0x...
```

### Default Behavior

If `CNS_PAUSER` or `CNS_ALLOWLIST_ADMIN` are not set, they default to the multisig address. This is acceptable for initial deployment, but operational roles should be separated for production use.

## Deployment Process

### 1. Verify Configuration

```bash
# Source environment
source .env

# Verify all addresses are set
echo "Multisig: $CNS_MULTISIG"
echo "Pauser: $CNS_PAUSER"
echo "Allowlist Admin: $CNS_ALLOWLIST_ADMIN"
echo "L1 Token: $CNS_TOKEN_L1"
echo "Bridge: $LINEA_L2_BRIDGE"
```

### 2. Dry Run (Simulation)

```bash
forge script script/2_DeployCNSTokenL2.s.sol:DeployCNSTokenL2 \
  --rpc-url $RPC_URL
```

Review the output carefully. You should see:

```
=== Deploying CNS Token L2 with Role Separation ===
Token Name: CNS Linea Token
Token Symbol: CNSL
Decimals: 18

=== Role Assignment ===
Multisig (Admin + Upgrader): 0x...
Pauser: 0x...
Allowlist Admin: 0x...

=== Contract Addresses ===
L1 Token: 0x...
Bridge: 0x...
```

### 3. Deploy to Network

```bash
forge script script/2_DeployCNSTokenL2.s.sol:DeployCNSTokenL2 \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

### 4. Verify Deployment

The script automatically verifies:
- ✅ Multisig has `DEFAULT_ADMIN_ROLE` and `UPGRADER_ROLE`
- ✅ Pauser has `PAUSER_ROLE`
- ✅ Allowlist Admin has `ALLOWLIST_ADMIN_ROLE`
- ✅ Multisig has backup access to operational roles
- ✅ Bridge, token contract, and multisig are allowlisted
- ✅ Initialization is complete and secure

## Safe CLI Testing

### Connect to Your Safe

```bash
# Connect Safe CLI to your deployed Safe
safe-cli linea_sepolia <YOUR_SAFE_ADDRESS>
```

### Basic Operations

#### Check Safe Status

```bash
> info
# Shows owners, threshold, nonce, balance

> get_owners
# Lists all Safe owners

> get_threshold
# Shows required signature threshold
```

#### Pause Contract (Emergency)

```bash
# Create transaction to pause
> send_ether <TOKEN_ADDRESS> 0
> send_custom <TOKEN_ADDRESS> 0 pause()

# Sign transaction
> sign_transaction <TX_HASH>

# Get another signer to sign
# Then execute when threshold reached
> execute_transaction <TX_HASH>
```

#### Add Address to Allowlist

```bash
# Encode function call
> send_custom <TOKEN_ADDRESS> 0 setSenderAllowed(address,bool) <ADDRESS> true

# Sign and execute as above
```

#### Upgrade Contract (Critical Operation)

```bash
# Deploy new implementation first
NEW_IMPL=0x...

# Create upgrade transaction
> send_custom <TOKEN_ADDRESS> 0 upgradeToAndCall(address,bytes) $NEW_IMPL 0x

# Collect required signatures
> sign_transaction <TX_HASH>

# Execute when threshold reached
> execute_transaction <TX_HASH>
```

### Testing Scenario: Full Workflow

1. **Deploy Safe** (3-of-5)
2. **Deploy Token** with Safe as multisig
3. **Test Pause** via Safe
4. **Test Allowlist** management via Safe
5. **Test Upgrade** via Safe (if needed)

Example test script:

```bash
#!/bin/bash
# test-multisig-workflow.sh

set -e

SAFE_ADDRESS=$CNS_MULTISIG
TOKEN_ADDRESS=<deployed-token>

echo "Testing multisig workflow..."

# Test 1: Check Safe owners
safe-cli linea_sepolia $SAFE_ADDRESS --command "get_owners"

# Test 2: Pause contract (requires 3 signatures)
echo "Creating pause transaction..."
safe-cli linea_sepolia $SAFE_ADDRESS --command "send_custom $TOKEN_ADDRESS 0 pause()"

# Test 3: Unpause contract
echo "Creating unpause transaction..."
safe-cli linea_sepolia $SAFE_ADDRESS --command "send_custom $TOKEN_ADDRESS 0 unpause()"

# Test 4: Add to allowlist
echo "Adding address to allowlist..."
NEW_ADDRESS=0x1234567890123456789012345678901234567890
safe-cli linea_sepolia $SAFE_ADDRESS --command "send_custom $TOKEN_ADDRESS 0 setSenderAllowed(address,bool) $NEW_ADDRESS true"

echo "Test transactions created. Sign and execute them via Safe CLI or UI."
```

## Production Recommendations

### Multisig Configuration

- **Threshold**: 3-of-5 minimum, 4-of-7 recommended
- **Owners**: Distribute across:
  - Different geographical locations
  - Different organizations/individuals
  - Hardware wallets (Ledger, Trezor)
  - Different key management solutions

### Operational Roles

- **Pauser**: 
  - Hot wallet for fast emergency response
  - Keep private key in secure but accessible location
  - Consider 2-of-3 for pauser role (advanced)
  
- **Allowlist Admin**:
  - Operational hot wallet
  - Automated backend can use this for routine allowlist updates
  - Log all allowlist changes off-chain

### Security Best Practices

1. **Never share private keys**
2. **Test all operations on testnet first**
3. **Document all multisig transactions**
4. **Maintain offline backups of Safe owners**
5. **Regular security audits of access control**
6. **Monitor on-chain events for unauthorized access**
7. **Have incident response plan ready**

### Monitoring

Set up monitoring for:
- Role changes (using `RoleGranted`, `RoleRevoked` events)
- Pause/Unpause events
- Upgrade events
- Allowlist changes

Example monitoring setup:

```typescript
// Monitor role changes
contract.on(contract.filters.RoleGranted(), (role, account, sender, event) => {
  console.warn(`Role ${role} granted to ${account} by ${sender}`);
  // Alert to security team
});

// Monitor pauses
contract.on("Paused", (account, event) => {
  console.error(`Contract paused by ${account}`);
  // Alert to all teams
});
```

### Upgrade Process

1. **Deploy new implementation** to testnet
2. **Test thoroughly** on testnet
3. **Security audit** of new implementation
4. **Deploy to mainnet** (via multisig)
5. **Create upgrade proposal** in Safe
6. **Collect required signatures**
7. **Execute upgrade** during low-traffic period
8. **Verify upgrade** success
9. **Monitor** for issues

### Recovery Procedures

If operational keys are compromised:

1. **Immediately pause** contract using multisig backup
2. **Revoke compromised role** using multisig
3. **Grant role to new address**
4. **Update operational procedures**
5. **Post-incident analysis**

## Troubleshooting

### Safe CLI Connection Issues

```bash
# Check Safe exists on network
cast code $CNS_MULTISIG --rpc-url $RPC_URL

# Verify Safe owners
cast call $CNS_MULTISIG "getOwners()(address[])" --rpc-url $RPC_URL
```

### Transaction Not Executing

- Verify threshold is met
- Check Safe has enough ETH for gas
- Ensure transaction nonce is correct
- Review transaction data encoding

### Role Assignment Issues

```bash
# Check if address has role
cast call $TOKEN_ADDRESS "hasRole(bytes32,address)(bool)" \
  0x0000000000000000000000000000000000000000000000000000000000000000 \
  $CNS_MULTISIG \
  --rpc-url $RPC_URL
```

## Additional Resources

- [Gnosis Safe Documentation](https://docs.safe.global/)
- [Safe CLI Repository](https://github.com/safe-global/safe-cli)
- [OpenZeppelin AccessControl](https://docs.openzeppelin.com/contracts/4.x/access-control)
- [Linea Documentation](https://docs.linea.build/)

## Support

For issues or questions:
1. Review this guide thoroughly
2. Check deployment logs and verification output
3. Test on testnet first
4. Consult team security procedures


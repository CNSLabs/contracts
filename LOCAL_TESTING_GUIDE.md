# Local Testing Guide with Anvil

This guide shows you how to test CNS token deployments locally using Anvil before deploying to testnet/mainnet.

## Quick Start

```bash
# Terminal 1: Start Anvil
anvil

# Terminal 2: Run deployment scripts
cd contract-prototyping

# Deploy L1 token
forge script script/1_DeployShoTokenL1.s.sol:DeployShoTokenL1 \
  --rpc-url http://localhost:8545 \
  --broadcast

# Deploy L2 token (after setting SHO_TOKEN_L1)
forge script script/2_DeployShoTokenL2.s.sol:DeployShoTokenL2 \
  --rpc-url http://localhost:8545 \
  --broadcast
```

## Step-by-Step Guide

### Step 1: Start Anvil

Open a terminal and start Anvil:

```bash
anvil
```

You should see output like:
```
Available Accounts
==================

(0) 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 (10000.000000000000000000 ETH)
(1) 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 (10000.000000000000000000 ETH)
...

Private Keys
==================

(0) 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
(1) 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
...

Listening on 127.0.0.1:8545
```

**Keep this terminal running!**

### Step 2: Set Up Local Environment Variables

Create a `.env.local` file for testing (don't commit this):

```bash
# .env.local - for local Anvil testing
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Use second Anvil account as owner
SHO_OWNER=0x70997970C51812dc3A010C7d01b50e0d17dc79C8

# For L2 deployment, use any address as mock bridge
LINEA_L2_BRIDGE=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC

# Will be set after L1 deployment
SHO_TOKEN_L1=

# Will be set after L2 deployment
SHO_TOKEN_L2_PROXY=

# Not needed for local testing
MAINNET_DEPLOYMENT_ALLOWED=false
```

Load the environment:
```bash
source .env.local
```

### Step 3: Deploy L1 Token

In a **second terminal**:

```bash
cd /Users/vlado/projects/contract-prototyping

# Source your local env
source .env.local

# Deploy L1 token
forge script script/1_DeployShoTokenL1.s.sol:DeployShoTokenL1 \
  --rpc-url http://localhost:8545 \
  --broadcast
```

**Expected output:**
```
=== Deploying CNS Token L1 ===
Network: Local Anvil
Chain ID: 31337
...
ShoTokenL1: 0x5FbDB2315678afecb367f032d93F642f64180aa3
Owner Balance: 100000000 tokens
Total Supply: 100000000 tokens
```

**Save the L1 token address!**

```bash
export SHO_TOKEN_L1=0x5FbDB2315678afecb367f032d93F642f64180aa3  # Use your actual address
```

### Step 4: Deploy L2 Token

Now deploy the L2 token (in the same terminal):

```bash
# Make sure SHO_TOKEN_L1 is set from Step 3
echo $SHO_TOKEN_L1

# Deploy L2 token
forge script script/2_DeployShoTokenL2.s.sol:DeployShoTokenL2 \
  --rpc-url http://localhost:8545 \
  --broadcast
```

**Expected output:**
```
=== Deploying CNS Token L2 ===
Network: Local Anvil
Chain ID: 31337
...
Implementation: 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
Proxy (Token): 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
...
[SUCCESS] All deployment checks passed!
```

**Save the L2 proxy address!**

```bash
export SHO_TOKEN_L2_PROXY=0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0  # Use your actual address
```

### Step 5: Test the Deployed Contracts

#### Test L1 Token

```bash
# Check balance of owner
cast call $SHO_TOKEN_L1 "balanceOf(address)" $SHO_OWNER --rpc-url http://localhost:8545

# Check token name
cast call $SHO_TOKEN_L1 "name()" --rpc-url http://localhost:8545

# Check token symbol  
cast call $SHO_TOKEN_L1 "symbol()" --rpc-url http://localhost:8545

# Transfer tokens from owner to another address
cast send $SHO_TOKEN_L1 \
  "transfer(address,uint256)" \
  0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  1000000000000000000 \
  --private-key 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d \
  --rpc-url http://localhost:8545
```

#### Test L2 Token

```bash
# Check token name
cast call $SHO_TOKEN_L2_PROXY "name()" --rpc-url http://localhost:8545

# Check if owner is allowlisted
cast call $SHO_TOKEN_L2_PROXY "isAllowlisted(address)" $SHO_OWNER --rpc-url http://localhost:8545

# Add a new address to allowlist (as owner)
OWNER_PK=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
USER1=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

cast send $SHO_TOKEN_L2_PROXY \
  "setAllowlist(address,bool)" \
  $USER1 \
  true \
  --private-key $OWNER_PK \
  --rpc-url http://localhost:8545

# Simulate minting (as bridge)
BRIDGE_PK=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a  # Account 2
cast send $SHO_TOKEN_L2_PROXY \
  "mint(address,uint256)" \
  $SHO_OWNER \
  1000000000000000000 \
  --private-key $BRIDGE_PK \
  --rpc-url http://localhost:8545

# Check balance
cast call $SHO_TOKEN_L2_PROXY "balanceOf(address)" $SHO_OWNER --rpc-url http://localhost:8545

# Try transfer between allowlisted addresses
cast send $SHO_TOKEN_L2_PROXY \
  "transfer(address,uint256)" \
  $USER1 \
  100000000000000000 \
  --private-key $OWNER_PK \
  --rpc-url http://localhost:8545
```

### Step 6: Test Upgrade to V2 (Optional)

```bash
# Make sure SHO_TOKEN_L2_PROXY is set
echo $SHO_TOKEN_L2_PROXY

# IMPORTANT: Switch to owner's private key (owner has UPGRADER_ROLE)
export PRIVATE_KEY=$OWNER_PK

# Upgrade to V2
forge script script/3_UpgradeShoTokenL2ToV2_Schedule.s.sol:UpgradeShoTokenL2ToV2_Schedule \
  --rpc-url http://localhost:8545 \
  --broadcast

# Switch back if needed
export PRIVATE_KEY=$DEPLOYER_PK

# Test V2 features (delegation)
cast send $SHO_TOKEN_L2_PROXY \
  "delegate(address)" \
  $SHO_OWNER \
  --private-key $OWNER_PK \
  --rpc-url http://localhost:8545

# Check voting power
cast call $SHO_TOKEN_L2_PROXY "getVotes(address)" $SHO_OWNER --rpc-url http://localhost:8545
```

## Complete Test Script

Save this as `test-local-deployment.sh`:

```bash
#!/bin/bash
set -e

echo "🧪 Testing CNS Token Deployment Locally"
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Anvil accounts
DEPLOYER_PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
OWNER=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
OWNER_PK=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
BRIDGE=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
BRIDGE_PK=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a  # Account 2's key
USER1=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

RPC=http://localhost:8545

# Set environment
export PRIVATE_KEY=$DEPLOYER_PK
export SHO_OWNER=$OWNER
export LINEA_L2_BRIDGE=$BRIDGE

echo -e "${BLUE}Step 1: Deploying L1 Token${NC}"
forge script script/1_DeployShoTokenL1.s.sol:DeployShoTokenL1 \
  --rpc-url $RPC \
  --broadcast \
  --silent 2>/dev/null

# Extract L1 token address from broadcast
SHO_TOKEN_L1=$(jq -r '.transactions[0].contractAddress' broadcast/1_DeployShoTokenL1.s.sol/31337/run-latest.json)
echo -e "${GREEN}✓ L1 Token deployed: $SHO_TOKEN_L1${NC}"
export SHO_TOKEN_L1

echo ""
echo -e "${BLUE}Step 2: Deploying L2 Token${NC}"
forge script script/2_DeployShoTokenL2.s.sol:DeployShoTokenL2 \
  --rpc-url $RPC \
  --broadcast \
  --silent 2>/dev/null

# Extract L2 proxy address
SHO_TOKEN_L2_PROXY=$(jq -r '.transactions[-1].contractAddress' broadcast/2_DeployShoTokenL2.s.sol/31337/run-latest.json)
echo -e "${GREEN}✓ L2 Token deployed: $SHO_TOKEN_L2_PROXY${NC}"
export SHO_TOKEN_L2_PROXY

echo ""
echo -e "${BLUE}Step 3: Testing L1 Token${NC}"
OWNER_BALANCE=$(cast call $SHO_TOKEN_L1 "balanceOf(address)(uint256)" $OWNER --rpc-url $RPC)
echo -e "${GREEN}✓ Owner L1 balance: $OWNER_BALANCE${NC}"

echo ""
echo -e "${BLUE}Step 4: Testing L2 Token - Allowlist${NC}"
cast send $SHO_TOKEN_L2_PROXY "setAllowlist(address,bool)" $USER1 true \
  --private-key $OWNER_PK --rpc-url $RPC > /dev/null 2>&1
echo -e "${GREEN}✓ Added $USER1 to allowlist${NC}"

echo ""
echo -e "${BLUE}Step 5: Testing L2 Token - Minting${NC}"
cast send $SHO_TOKEN_L2_PROXY "mint(address,uint256)" $OWNER 1000000000000000000 \
  --private-key $BRIDGE_PK --rpc-url $RPC > /dev/null 2>&1
L2_BALANCE=$(cast call $SHO_TOKEN_L2_PROXY "balanceOf(address)(uint256)" $OWNER --rpc-url $RPC)
echo -e "${GREEN}✓ Minted tokens. Owner L2 balance: $L2_BALANCE${NC}"

echo ""
echo -e "${BLUE}Step 6: Testing L2 Token - Transfer${NC}"
cast send $SHO_TOKEN_L2_PROXY "transfer(address,uint256)" $USER1 100000000000000000 \
  --private-key $OWNER_PK --rpc-url $RPC > /dev/null 2>&1
USER1_BALANCE=$(cast call $SHO_TOKEN_L2_PROXY "balanceOf(address)(uint256)" $USER1 --rpc-url $RPC)
echo -e "${GREEN}✓ Transferred tokens. User1 balance: $USER1_BALANCE${NC}"

echo ""
echo -e "${BLUE}Step 7: Upgrading to V2${NC}"
forge script script/3_UpgradeShoTokenL2ToV2_Schedule.s.sol:UpgradeShoTokenL2ToV2_Schedule \
  --rpc-url $RPC \
  --broadcast \
  --silent 2>/dev/null
echo -e "${GREEN}✓ Upgraded to V2${NC}"

echo ""
echo -e "${BLUE}Step 8: Testing V2 - Delegation${NC}"
cast send $SHO_TOKEN_L2_PROXY "delegate(address)" $OWNER \
  --private-key $OWNER_PK --rpc-url $RPC > /dev/null 2>&1
VOTES=$(cast call $SHO_TOKEN_L2_PROXY "getVotes(address)(uint256)" $OWNER --rpc-url $RPC)
echo -e "${GREEN}✓ Delegated. Owner voting power: $VOTES${NC}"

echo ""
echo -e "${GREEN}✅ All tests passed!${NC}"
echo ""
echo "Deployed Addresses:"
echo "  L1 Token: $SHO_TOKEN_L1"
echo "  L2 Proxy: $SHO_TOKEN_L2_PROXY"
```

Make it executable and run:

```bash
chmod +x test-local-deployment.sh

# Make sure Anvil is running in another terminal!
./test-local-deployment.sh
```

## Interactive Testing with Cast

Once deployed, you can interact with the contracts using `cast`:

### Useful Cast Commands

```bash
# Get token info
cast call $SHO_TOKEN_L1 "name()(string)" --rpc-url http://localhost:8545
cast call $SHO_TOKEN_L1 "symbol()(string)" --rpc-url http://localhost:8545
cast call $SHO_TOKEN_L1 "totalSupply()(uint256)" --rpc-url http://localhost:8545

# Check balances
cast call $SHO_TOKEN_L1 "balanceOf(address)(uint256)" $SHO_OWNER --rpc-url http://localhost:8545

# Check roles on L2
ADMIN_ROLE=0x0000000000000000000000000000000000000000000000000000000000000000
cast call $SHO_TOKEN_L2_PROXY "hasRole(bytes32,address)(bool)" $ADMIN_ROLE $SHO_OWNER --rpc-url http://localhost:8545

# Check allowlist
cast call $SHO_TOKEN_L2_PROXY "isAllowlisted(address)(bool)" $SHO_OWNER --rpc-url http://localhost:8545

# Pause L2 token
cast send $SHO_TOKEN_L2_PROXY "pause()" --private-key $OWNER_PK --rpc-url http://localhost:8545

# Unpause
cast send $SHO_TOKEN_L2_PROXY "unpause()" --private-key $OWNER_PK --rpc-url http://localhost:8545
```

## Important Notes

### UPGRADER_ROLE and Private Keys

**Key Point**: The L2 token grants `UPGRADER_ROLE` to the `SHO_OWNER` during deployment, **not** to the deployer.

This means:
- 🔐 **For upgrades**, you must use the private key of the account that has `UPGRADER_ROLE` (typically `SHO_OWNER`)
- 👷 **For deployments**, you can use any account with enough ETH (the deployer)

In our local test setup:
- Deployer (Account 0): Used for initial deployments
- Owner (Account 1): Has all admin roles including `UPGRADER_ROLE`

When upgrading, make sure to:
```bash
export PRIVATE_KEY=$OWNER_PRIVATE_KEY  # Use owner's key, not deployer's
forge script script/3_UpgradeShoTokenL2ToV2_Schedule.s.sol:UpgradeShoTokenL2ToV2_Schedule --rpc-url ... --broadcast
```

This is a **security feature** - it separates the deployment permission (anyone) from the upgrade permission (only authorized accounts).

## Tips & Tricks

### 1. Reset Anvil State

If you want to start fresh:
```bash
# Stop Anvil (Ctrl+C)
# Start it again
anvil
```

### 2. Use Different Ports

Run multiple Anvil instances:
```bash
# Terminal 1: Anvil for "L1"
anvil --port 8545

# Terminal 2: Anvil for "L2"  
anvil --port 8546

# Deploy to different ports
forge script ... --rpc-url http://localhost:8545 --broadcast  # L1
forge script ... --rpc-url http://localhost:8546 --broadcast  # L2
```

### 3. Fork Real Networks

Test against real state:
```bash
# Fork Sepolia
anvil --fork-url https://ethereum-sepolia-rpc.publicnode.com

# Fork Linea Sepolia
anvil --fork-url https://rpc.sepolia.linea.build --port 8546
```

### 4. Enable Verbose Logging

See all transactions:
```bash
forge script ... --rpc-url http://localhost:8545 --broadcast -vvvv
```

### 5. Check Transaction Receipts

```bash
# Get transaction receipt
cast receipt <TX_HASH> --rpc-url http://localhost:8545

# Get transaction details
cast tx <TX_HASH> --rpc-url http://localhost:8545
```

## Troubleshooting

### Issue: "Failed to get account"

**Solution**: Make sure Anvil is running:
```bash
curl http://localhost:8545 -X POST -H "Content-Type: application/json" \
  --data '{"method":"eth_blockNumber","params":[],"id":1,"jsonrpc":"2.0"}'
```

### Issue: "Nonce too high"

**Solution**: Reset Anvil or wait for the transaction to be mined.

### Issue: Contract not deploying

**Solution**: Check the logs with `-vvvv` flag:
```bash
forge script ... --rpc-url http://localhost:8545 --broadcast -vvvv
```

### Issue: "Missing environment variable"

**Solution**: Make sure all required variables are set:
```bash
echo $PRIVATE_KEY
echo $SHO_OWNER
echo $SHO_TOKEN_L1  # After L1 deployment
echo $LINEA_L2_BRIDGE
```

## Next Steps

After testing locally:
1. ✅ Test on Sepolia testnet
2. ✅ Verify contracts on Etherscan
3. ✅ Test bridging between L1 and L2
4. ✅ Deploy to mainnet

Happy testing! 🎉


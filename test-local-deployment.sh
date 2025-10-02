#!/bin/bash
set -e

echo "🧪 Testing CNS Token Deployment Locally with Anvil"
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Anvil default accounts
DEPLOYER_PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
OWNER=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
OWNER_PK=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
BRIDGE=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
BRIDGE_PK=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
USER1=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

RPC=http://localhost:8545

# Check Anvil
echo -e "${YELLOW}Checking if Anvil is running...${NC}"
if ! curl -s $RPC -X POST -H "Content-Type: application/json" \
  --data '{"method":"eth_blockNumber","params":[],"id":1,"jsonrpc":"2.0"}' > /dev/null 2>&1; then
  echo -e "${RED}❌ Anvil is not running!${NC}"
  echo -e "${YELLOW}Start Anvil in another terminal: anvil${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Anvil is running${NC}"
echo ""

# Set environment
export PRIVATE_KEY=$DEPLOYER_PK
export CNS_OWNER=$OWNER
export LINEA_L2_BRIDGE=$BRIDGE

# Deploy L1 Token
echo -e "${BLUE}Step 1: Deploying L1 Token${NC}"
forge script script/1_DeployCNSTokenL1.s.sol:DeployCNSTokenL1 \
  --rpc-url $RPC --broadcast > /dev/null 2>&1

CNS_TOKEN_L1=$(jq -r '.transactions[0].contractAddress' broadcast/1_DeployCNSTokenL1.s.sol/31337/run-latest.json)
echo -e "${GREEN}✅ L1 Token: $CNS_TOKEN_L1${NC}"
export CNS_TOKEN_L1

# Deploy L2 Token
echo ""
echo -e "${BLUE}Step 2: Deploying L2 Token${NC}"
forge script script/2_DeployCNSTokenL2.s.sol:DeployCNSTokenL2 \
  --rpc-url $RPC --broadcast > /dev/null 2>&1

CNS_TOKEN_L2_PROXY=$(jq -r '.transactions[-1].contractAddress' broadcast/2_DeployCNSTokenL2.s.sol/31337/run-latest.json)
echo -e "${GREEN}✅ L2 Proxy: $CNS_TOKEN_L2_PROXY${NC}"
export CNS_TOKEN_L2_PROXY

# Test Allowlist
echo ""
echo -e "${BLUE}Step 3: Testing Allowlist${NC}"
cast send $CNS_TOKEN_L2_PROXY "setAllowlist(address,bool)" $USER1 true \
  --private-key $OWNER_PK --rpc-url $RPC > /dev/null 2>&1
echo -e "${GREEN}✅ Added user to allowlist${NC}"

# Test Minting
echo ""
echo -e "${BLUE}Step 4: Testing Bridge Minting${NC}"
cast send $CNS_TOKEN_L2_PROXY "mint(address,uint256)" $OWNER 1000000000000000000 \
  --private-key $BRIDGE_PK --rpc-url $RPC > /dev/null 2>&1
L2_BALANCE=$(cast call $CNS_TOKEN_L2_PROXY "balanceOf(address)(uint256)" $OWNER --rpc-url $RPC)
echo -e "${GREEN}✅ Minted 1 token. Balance: $L2_BALANCE wei${NC}"

# Test Transfer
echo ""
echo -e "${BLUE}Step 5: Testing Transfer${NC}"
cast send $CNS_TOKEN_L2_PROXY "transfer(address,uint256)" $USER1 100000000000000000 \
  --private-key $OWNER_PK --rpc-url $RPC > /dev/null 2>&1
USER1_BALANCE=$(cast call $CNS_TOKEN_L2_PROXY "balanceOf(address)(uint256)" $USER1 --rpc-url $RPC)
echo -e "${GREEN}✅ Transferred 0.1 token. User balance: $USER1_BALANCE wei${NC}"

# Test Pause
echo ""
echo -e "${BLUE}Step 6: Testing Pause${NC}"
cast send $CNS_TOKEN_L2_PROXY "pause()" --private-key $OWNER_PK --rpc-url $RPC > /dev/null 2>&1
echo -e "${GREEN}✅ Token paused${NC}"
cast send $CNS_TOKEN_L2_PROXY "unpause()" --private-key $OWNER_PK --rpc-url $RPC > /dev/null 2>&1
echo -e "${GREEN}✅ Token unpaused${NC}"

# Upgrade to V2
echo ""
echo -e "${BLUE}Step 7: Upgrading to V2${NC}"
export PRIVATE_KEY=$OWNER_PK
forge script script/3_UpgradeCNSTokenL2ToV2.s.sol:UpgradeCNSTokenL2ToV2 \
  --rpc-url $RPC --broadcast > /dev/null 2>&1
echo -e "${GREEN}✅ Upgraded to V2${NC}"

# Test V2 Features
echo ""
echo -e "${BLUE}Step 8: Testing V2 Voting${NC}"
cast send $CNS_TOKEN_L2_PROXY "delegate(address)" $OWNER \
  --private-key $OWNER_PK --rpc-url $RPC > /dev/null 2>&1
VOTES=$(cast call $CNS_TOKEN_L2_PROXY "getVotes(address)(uint256)" $OWNER --rpc-url $RPC)
echo -e "${GREEN}✅ Delegated. Voting power: $VOTES wei${NC}"

# Summary
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ All Tests Passed!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "📝 Deployed Addresses:"
echo "  L1 Token:    $CNS_TOKEN_L1"
echo "  L2 Proxy:    $CNS_TOKEN_L2_PROXY"
echo ""
echo "💡 Interact with contracts using cast:"
echo "  cast call $CNS_TOKEN_L1 \"balanceOf(address)\" $OWNER --rpc-url $RPC"
echo "  cast call $CNS_TOKEN_L2_PROXY \"getVotes(address)\" $OWNER --rpc-url $RPC"
echo ""

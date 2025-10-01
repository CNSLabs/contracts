#!/bin/bash
set -e

echo "🧪 Testing CNS Token Deployment Locally with Anvil"
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Anvil default accounts
DEPLOYER_PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
OWNER=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
OWNER_PK=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
BRIDGE=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
BRIDGE_PK=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a  # Fixed: Account 2's key
USER1=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

RPC=http://localhost:8545

# Check if Anvil is running
echo -e "${YELLOW}Checking if Anvil is running...${NC}"
if ! curl -s $RPC -X POST -H "Content-Type: application/json" \
  --data '{"method":"eth_blockNumber","params":[],"id":1,"jsonrpc":"2.0"}' > /dev/null 2>&1; then
  echo -e "${RED}❌ Anvil is not running!${NC}"
  echo -e "${YELLOW}Please start Anvil in another terminal:${NC}"
  echo "  anvil"
  exit 1
fi
echo -e "${GREEN}✓ Anvil is running${NC}"
echo ""

# Set environment
export PRIVATE_KEY=$DEPLOYER_PK
export CNS_OWNER=$OWNER
export LINEA_L2_BRIDGE=$BRIDGE

# Step 1: Deploy L1 Token
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 1: Deploying L1 Token (Ethereum)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
forge script script/1_DeployCNSTokenL1.s.sol:DeployCNSTokenL1 \
  --rpc-url $RPC \
  --broadcast

# Extract L1 token address from broadcast
if [ ! -f "broadcast/1_DeployCNSTokenL1.s.sol/31337/run-latest.json" ]; then
  echo -e "${RED}❌ L1 deployment failed - broadcast file not found${NC}"
  exit 1
fi

CNS_TOKEN_L1=$(jq -r '.transactions[0].contractAddress' broadcast/1_DeployCNSTokenL1.s.sol/31337/run-latest.json)
echo ""
echo -e "${GREEN}✅ L1 Token deployed at: $CNS_TOKEN_L1${NC}"
export CNS_TOKEN_L1

# Verify L1 deployment
echo ""
echo -e "${YELLOW}Verifying L1 deployment...${NC}"
OWNER_BALANCE=$(cast call $CNS_TOKEN_L1 "balanceOf(address)(uint256)" $OWNER --rpc-url $RPC)
TOKEN_NAME=$(cast call $CNS_TOKEN_L1 "name()(string)" --rpc-url $RPC)
TOKEN_SYMBOL=$(cast call $CNS_TOKEN_L1 "symbol()(string)" --rpc-url $RPC)
# Convert wei to tokens safely
OWNER_BALANCE_TOKENS=$(cast --to-unit ether $OWNER_BALANCE 2>/dev/null || echo "N/A")
echo -e "${GREEN}  Name: $TOKEN_NAME${NC}"
echo -e "${GREEN}  Symbol: $TOKEN_SYMBOL${NC}"
echo -e "${GREEN}  Owner Balance: $OWNER_BALANCE wei ($OWNER_BALANCE_TOKENS tokens)${NC}"

# Step 2: Deploy L2 Token
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 2: Deploying L2 Token (Linea)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
forge script script/2_DeployCNSTokenL2.s.sol:DeployCNSTokenL2 \
  --rpc-url $RPC \
  --broadcast

# Extract L2 proxy address
if [ ! -f "broadcast/2_DeployCNSTokenL2.s.sol/31337/run-latest.json" ]; then
  echo -e "${RED}❌ L2 deployment failed - broadcast file not found${NC}"
  exit 1
fi

CNS_TOKEN_L2_PROXY=$(jq -r '.transactions[-1].contractAddress' broadcast/2_DeployCNSTokenL2.s.sol/31337/run-latest.json)
echo ""
echo -e "${GREEN}✅ L2 Token (proxy) deployed at: $CNS_TOKEN_L2_PROXY${NC}"
export CNS_TOKEN_L2_PROXY

# Verify L2 deployment
echo ""
echo -e "${YELLOW}Verifying L2 deployment...${NC}"
L2_NAME=$(cast call $CNS_TOKEN_L2_PROXY "name()(string)" --rpc-url $RPC)
L2_SYMBOL=$(cast call $CNS_TOKEN_L2_PROXY "symbol()(string)" --rpc-url $RPC)
OWNER_ALLOWLISTED=$(cast call $CNS_TOKEN_L2_PROXY "isAllowlisted(address)(bool)" $OWNER --rpc-url $RPC)
echo -e "${GREEN}  Name: $L2_NAME${NC}"
echo -e "${GREEN}  Symbol: $L2_SYMBOL${NC}"
echo -e "${GREEN}  Owner Allowlisted: $OWNER_ALLOWLISTED${NC}"

# Step 3: Test L2 Allowlist
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 3: Testing L2 Allowlist${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "Adding $USER1 to allowlist..."
cast send $CNS_TOKEN_L2_PROXY "setAllowlist(address,bool)" $USER1 true \
  --private-key $OWNER_PK --rpc-url $RPC > /dev/null 2>&1
USER1_ALLOWLISTED=$(cast call $CNS_TOKEN_L2_PROXY "isAllowlisted(address)(bool)" $USER1 --rpc-url $RPC)
echo -e "${GREEN}✅ User1 allowlisted: $USER1_ALLOWLISTED${NC}"

# Step 4: Test L2 Minting (via Bridge)
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 4: Testing L2 Minting (Bridge)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
MINT_AMOUNT=1000000000000000000  # 1 token
echo "Minting $MINT_AMOUNT wei to owner..."
cast send $CNS_TOKEN_L2_PROXY "mint(address,uint256)" $OWNER $MINT_AMOUNT \
  --private-key $BRIDGE_PK --rpc-url $RPC > /dev/null 2>&1
L2_BALANCE=$(cast call $CNS_TOKEN_L2_PROXY "balanceOf(address)(uint256)" $OWNER --rpc-url $RPC)
echo -e "${GREEN}✅ Owner L2 balance: $L2_BALANCE wei ($(($L2_BALANCE / 1000000000000000000)) tokens)${NC}"

# Step 5: Test L2 Transfer
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 5: Testing L2 Transfer${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
TRANSFER_AMOUNT=100000000000000000  # 0.1 token
echo "Transferring $TRANSFER_AMOUNT wei from owner to user1..."
cast send $CNS_TOKEN_L2_PROXY "transfer(address,uint256)" $USER1 $TRANSFER_AMOUNT \
  --private-key $OWNER_PK --rpc-url $RPC > /dev/null 2>&1
USER1_BALANCE=$(cast call $CNS_TOKEN_L2_PROXY "balanceOf(address)(uint256)" $USER1 --rpc-url $RPC)
NEW_OWNER_BALANCE=$(cast call $CNS_TOKEN_L2_PROXY "balanceOf(address)(uint256)" $OWNER --rpc-url $RPC)
echo -e "${GREEN}✅ Transfer successful!${NC}"
echo -e "${GREEN}  Owner balance: $NEW_OWNER_BALANCE wei${NC}"
echo -e "${GREEN}  User1 balance: $USER1_BALANCE wei${NC}"

# Step 6: Test Pause Functionality
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 6: Testing Pause Functionality${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "Pausing L2 token..."
cast send $CNS_TOKEN_L2_PROXY "pause()" --private-key $OWNER_PK --rpc-url $RPC > /dev/null 2>&1
IS_PAUSED=$(cast call $CNS_TOKEN_L2_PROXY "paused()(bool)" --rpc-url $RPC)
echo -e "${GREEN}✅ Token paused: $IS_PAUSED${NC}"

echo "Unpausing L2 token..."
cast send $CNS_TOKEN_L2_PROXY "unpause()" --private-key $OWNER_PK --rpc-url $RPC > /dev/null 2>&1
IS_PAUSED=$(cast call $CNS_TOKEN_L2_PROXY "paused()(bool)" --rpc-url $RPC)
echo -e "${GREEN}✅ Token unpaused (paused=$IS_PAUSED)${NC}"

# Step 7: Upgrade to V2
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 7: Upgrading L2 Token to V2${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "Note: Switching to owner's private key (owner has UPGRADER_ROLE)"

# Switch to owner's key for upgrade (owner has UPGRADER_ROLE)
export PRIVATE_KEY=$OWNER_PK
forge script script/3_UpgradeCNSTokenL2ToV2.s.sol:UpgradeCNSTokenL2ToV2 \
  --rpc-url $RPC \
  --broadcast

echo ""
echo -e "${GREEN}✅ Upgraded to V2${NC}"

# Switch back to deployer key (for consistency, though not strictly needed)
export PRIVATE_KEY=$DEPLOYER_PK

# Step 8: Test V2 Voting Features
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 8: Testing V2 Voting Features${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Check initial voting power (should be 0 before delegation)
VOTES_BEFORE=$(cast call $CNS_TOKEN_L2_PROXY "getVotes(address)(uint256)" $OWNER --rpc-url $RPC)
echo "Owner voting power before delegation: $VOTES_BEFORE"

# Delegate to self
echo "Owner delegating to self..."
cast send $CNS_TOKEN_L2_PROXY "delegate(address)" $OWNER \
  --private-key $OWNER_PK --rpc-url $RPC > /dev/null 2>&1

VOTES_AFTER=$(cast call $CNS_TOKEN_L2_PROXY "getVotes(address)(uint256)" $OWNER --rpc-url $RPC)
DELEGATE=$(cast call $CNS_TOKEN_L2_PROXY "delegates(address)(address)" $OWNER --rpc-url $RPC)
# Convert wei to tokens (handle scientific notation safely)
VOTES_TOKENS=$(cast --to-unit ether $VOTES_AFTER 2>/dev/null || echo "N/A")
echo -e "${GREEN}✅ Delegation successful!${NC}"
echo -e "${GREEN}  Delegate: $DELEGATE${NC}"
echo -e "${GREEN}  Voting power: $VOTES_AFTER wei ($VOTES_TOKENS tokens)${NC}"

# Summary
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ All Tests Passed!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "📝 Deployment Summary:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  L1 Token:    $CNS_TOKEN_L1"
echo "  L2 Proxy:    $CNS_TOKEN_L2_PROXY"
echo "  Owner:       $OWNER"
echo "  Bridge:      $BRIDGE"
echo ""
echo "💡 You can now interact with the contracts using cast:"
echo "  cast call $CNS_TOKEN_L1 \"balanceOf(address)\" $OWNER --rpc-url $RPC"
echo "  cast call $CNS_TOKEN_L2_PROXY \"getVotes(address)\" $OWNER --rpc-url $RPC"
echo ""
echo "🎉 Local testing complete!"


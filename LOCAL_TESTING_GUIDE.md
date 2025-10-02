# Local Testing Guide

Test CNS token deployments locally using Anvil before deploying to testnets.

## Automated Testing (Recommended)

```bash
# Terminal 1: Start Anvil
anvil

# Terminal 2: Run automated test suite
./test-local-deployment.sh
```

The script deploys L1, L2, tests all features, and upgrades to V2 automatically.

## Manual Step-by-Step

### 1. Start Anvil

```bash
anvil
```

Keep this terminal running. Anvil provides funded test accounts at `http://localhost:8545`.

### 2. Configure Environment

Create `.env.local` (don't commit):

```bash
# Anvil default accounts
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
CNS_OWNER=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
LINEA_L2_BRIDGE=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC

# Set after deployments
CNS_TOKEN_L1=
CNS_TOKEN_L2_PROXY=
```

Load environment:
```bash
source .env.local
```

### 3. Deploy L1 Token

```bash
forge script script/1_DeployCNSTokenL1.s.sol:DeployCNSTokenL1 \
  --rpc-url http://localhost:8545 \
  --broadcast

# Save the deployed address
export CNS_TOKEN_L1=0x5FbDB2315678afecb367f032d93F642f64180aa3
```

### 4. Deploy L2 Token

```bash
forge script script/2_DeployCNSTokenL2.s.sol:DeployCNSTokenL2 \
  --rpc-url http://localhost:8545 \
  --broadcast

# Save the proxy address
export CNS_TOKEN_L2_PROXY=0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
```

### 5. Test with Cast

```bash
# Check L1 balance
cast call $CNS_TOKEN_L1 "balanceOf(address)(uint256)" $CNS_OWNER --rpc-url http://localhost:8545

# Add user to L2 allowlist
OWNER_PK=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
USER1=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

cast send $CNS_TOKEN_L2_PROXY \
  "setAllowlist(address,bool)" $USER1 true \
  --private-key $OWNER_PK --rpc-url http://localhost:8545

# Mint tokens (as bridge)
BRIDGE_PK=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
cast send $CNS_TOKEN_L2_PROXY \
  "mint(address,uint256)" $CNS_OWNER 1000000000000000000 \
  --private-key $BRIDGE_PK --rpc-url http://localhost:8545

# Transfer between allowlisted addresses
cast send $CNS_TOKEN_L2_PROXY \
  "transfer(address,uint256)" $USER1 100000000000000000 \
  --private-key $OWNER_PK --rpc-url http://localhost:8545
```

### 6. Upgrade to V2

```bash
# Switch to owner's private key (has UPGRADER_ROLE)
export PRIVATE_KEY=$OWNER_PK

forge script script/3_UpgradeCNSTokenL2ToV2.s.sol:UpgradeCNSTokenL2ToV2 \
  --rpc-url http://localhost:8545 \
  --broadcast

# Test voting features
cast send $CNS_TOKEN_L2_PROXY "delegate(address)" $CNS_OWNER \
  --private-key $OWNER_PK --rpc-url http://localhost:8545

cast call $CNS_TOKEN_L2_PROXY "getVotes(address)(uint256)" $CNS_OWNER \
  --rpc-url http://localhost:8545
```

## Useful Cast Commands

```bash
# Token info
cast call $CNS_TOKEN_L1 "name()(string)" --rpc-url http://localhost:8545
cast call $CNS_TOKEN_L1 "symbol()(string)" --rpc-url http://localhost:8545
cast call $CNS_TOKEN_L1 "totalSupply()(uint256)" --rpc-url http://localhost:8545

# Check roles
ADMIN_ROLE=0x0000000000000000000000000000000000000000000000000000000000000000
cast call $CNS_TOKEN_L2_PROXY "hasRole(bytes32,address)(bool)" $ADMIN_ROLE $CNS_OWNER --rpc-url http://localhost:8545

# Pause/unpause
cast send $CNS_TOKEN_L2_PROXY "pause()" --private-key $OWNER_PK --rpc-url http://localhost:8545
cast send $CNS_TOKEN_L2_PROXY "unpause()" --private-key $OWNER_PK --rpc-url http://localhost:8545
```

## Advanced: Fork Real Networks

Test against real network state:

```bash
# Fork Sepolia
anvil --fork-url https://ethereum-sepolia-rpc.publicnode.com

# Fork Linea Sepolia
anvil --fork-url https://rpc.sepolia.linea.build --port 8546

# Then deploy to forked network
forge script ... --rpc-url http://localhost:8545 --broadcast
```

## Important Notes

### UPGRADER_ROLE

The L2 token grants `UPGRADER_ROLE` to `CNS_OWNER`, **not** the deployer.

For upgrades, you **must** use the owner's private key:
```bash
export PRIVATE_KEY=$OWNER_PK  # Not deployer's key!
forge script script/3_UpgradeCNSTokenL2ToV2.s.sol ...
```

This separates deployment permission (anyone with ETH) from upgrade permission (only authorized accounts).

## Troubleshooting

### Anvil not running
```bash
curl http://localhost:8545 -X POST -H "Content-Type: application/json" \
  --data '{"method":"eth_blockNumber","params":[],"id":1,"jsonrpc":"2.0"}'
```

### Missing environment variable
```bash
echo $PRIVATE_KEY
echo $CNS_OWNER
echo $CNS_TOKEN_L1
```

### See verbose logs
```bash
forge script ... --rpc-url http://localhost:8545 --broadcast -vvvv
```

### Reset Anvil
Stop (Ctrl+C) and restart `anvil` to start with fresh state.

## Next Steps

After successful local testing:
1. Deploy to Sepolia testnet
2. Verify contracts on Etherscan
3. Test bridging between L1 and L2
4. Deploy to mainnet with multisig

See [script/README.md](./script/README.md) for detailed deployment procedures.

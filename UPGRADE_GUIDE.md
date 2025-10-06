# Upgrade Guide for CNSTokenL2

## Overview

CNSTokenL2 uses the UUPS (Universal Upgradeable Proxy Standard) pattern, allowing the contract logic to be upgraded while preserving state. This guide covers safe upgrade procedures and best practices.

## Architecture

```
User → Proxy (ERC1967) → Implementation (CNSTokenL2)
         ↓ upgradeable
         Implementation V2 (CNSTokenL2V2)
```

**Key Components:**
- **Proxy**: Fixed address, delegates all calls to implementation
- **Implementation**: Upgradeable logic contract
- **Storage**: Lives in proxy, preserved across upgrades

## Pre-Upgrade Checklist

### 1. Storage Layout Verification
```bash
# Generate current storage layout
forge inspect CNSTokenL2 storage-layout > layouts/CNSTokenL2-v1.json

# Generate new version layout
forge inspect CNSTokenL2V2 storage-layout > layouts/CNSTokenL2V2-v2.json

# Compare layouts (manually verify no collisions)
diff layouts/CNSTokenL2-v1.json layouts/CNSTokenL2V2-v2.json
```

**Critical Rules:**
- ✅ Can ADD new variables at the end
- ✅ Can use storage gap slots
- ❌ CANNOT reorder existing variables
- ❌ CANNOT change variable types
- ❌ CANNOT remove variables
- ❌ CANNOT insert variables between existing ones

### 2. Run Upgrade Tests
```bash
# Run comprehensive upgrade test suite
forge test --match-contract CNSTokenL2UpgradeTest -vvv

# Run with gas report
forge test --match-contract CNSTokenL2UpgradeTest --gas-report

# Run specific upgrade test
forge test --match-test testUpgradePreservesAllState -vvv
```

### 3. Storage Gap Validation
```solidity
// Before upgrade, check gap size in CNSTokenL2:
uint256[47] private __gap;

// If adding N storage variables in V2:
// New gap size = 47 - N
uint256[47-N] private __gap; // Update accordingly
```

### 4. Audit Checklist
- [ ] Storage layout compatible (no collisions)
- [ ] Initializer logic correct (uses `reinitializer(X)` if needed)
- [ ] All tests pass (especially upgrade tests)
- [ ] Gas costs reviewed
- [ ] Access control unchanged or properly updated
- [ ] Events emitted for state changes
- [ ] No breaking changes to external interfaces

## Upgrade Procedures

### Local Testing (Anvil)

```bash
# 1. Start local node
anvil

# 2. Deploy V1 and initialize
forge script script/DeployCNSTokenL2.s.sol --rpc-url http://localhost:8545 --broadcast

# 3. Record proxy address from deployment
export PROXY_ADDRESS=0x...

# 4. Deploy V2 implementation
forge create src/CNSTokenL2V2.sol:CNSTokenL2V2 --rpc-url http://localhost:8545 --private-key $PRIVATE_KEY

# 5. Upgrade proxy to V2
cast send $PROXY_ADDRESS "upgradeToAndCall(address,bytes)" $NEW_IMPL_ADDRESS 0x --rpc-url http://localhost:8545 --private-key $PRIVATE_KEY

# 6. Verify upgrade
cast call $PROXY_ADDRESS "version()(uint256)" --rpc-url http://localhost:8545
```

### Testnet Upgrade (Linea Sepolia)

```bash
# 1. Deploy new implementation (DO NOT INITIALIZE)
forge create src/CNSTokenL2V2.sol:CNSTokenL2V2 \
  --rpc-url $L2_RPC_URL \
  --private-key $PRIVATE_KEY \
  --verify

# 2. Verify on block explorer
# Check: https://sepolia.lineascan.build/address/<IMPL_ADDRESS>

# 3. Prepare upgrade call (use multisig/timelock)
# Encode the upgrade call:
cast calldata "upgradeToAndCall(address,bytes)" $NEW_IMPL_ADDRESS 0x

# 4. Submit to multisig (Gnosis Safe)
# - Navigate to Safe web app
# - New Transaction > Contract Interaction
# - To: $PROXY_ADDRESS
# - Calldata: (from step 3)
# - Execute after review period

# 5. Verify upgrade succeeded
cast call $PROXY_ADDRESS "version()(uint256)" --rpc-url $L2_RPC_URL
```

### Mainnet Upgrade (Production)

**Prerequisites:**
- [ ] Audit completed and issues resolved
- [ ] Testnet upgrade successful
- [ ] Emergency pause plan ready
- [ ] Multisig signers coordinated
- [ ] Monitoring alerts configured

**Procedure:**
1. **Deploy Implementation** (via timelock/multisig)
   ```bash
   forge create src/CNSTokenL2V2.sol:CNSTokenL2V2 \
     --rpc-url $MAINNET_RPC_URL \
     --private-key $DEPLOYER_KEY \
     --verify
   ```

2. **Verify Implementation** (block explorer + manual)
   - Check contract code matches expected
   - Verify constructor args
   - Test on fork before mainnet

3. **Propose Upgrade** (via Gnosis Safe + Timelock)
   ```solidity
   // Create proposal in timelock
   timelock.schedule(
       target: proxyAddress,
       value: 0,
       data: abi.encodeWithSelector(
           UUPSUpgradeable.upgradeToAndCall.selector,
           newImplementation,
           ""
       ),
       delay: 2 days
   )
   ```

4. **Execute After Timelock**
   ```bash
   # After delay period
   cast send $TIMELOCK_ADDRESS "execute(...)" --rpc-url $MAINNET_RPC_URL
   ```

5. **Post-Upgrade Verification**
   ```bash
   # Verify version
   cast call $PROXY_ADDRESS "version()(uint256)"
   
   # Verify state preserved
   cast call $PROXY_ADDRESS "totalSupply()(uint256)"
   cast call $PROXY_ADDRESS "bridge()(address)"
   
   # Test critical functions
   # (transfer, mint, burn, pause, etc.)
   ```

## Upgrade Scenarios

### Adding New Storage Variables

```solidity
// V1
contract CNSTokenL2 {
    address public l1Token;
    mapping(address => bool) private _allowlisted;
    uint256[47] private __gap;
}

// V2 - Adding one variable
contract CNSTokenL2V2 {
    address public l1Token;
    mapping(address => bool) private _allowlisted;
    uint256 public newFeature;  // New variable
    uint256[46] private __gap;   // Gap reduced by 1
}
```

### Upgrading with Initialization

```solidity
contract CNSTokenL2V2 {
    uint256 public newFeature;
    
    function initializeV2(uint256 _initialValue) external reinitializer(2) {
        newFeature = _initialValue;
    }
}

// Upgrade call with initialization
bytes memory initData = abi.encodeWithSelector(
    CNSTokenL2V2.initializeV2.selector,
    100
);
proxy.upgradeToAndCall(newImplementation, initData);
```

### Emergency Rollback

If critical bug found post-upgrade:

```bash
# 1. Pause contract immediately
cast send $PROXY_ADDRESS "pause()" --private-key $PAUSER_KEY

# 2. Deploy previous version or fixed version
forge create src/CNSTokenL2.sol:CNSTokenL2 --rpc-url $RPC_URL

# 3. Upgrade to safe version
cast send $PROXY_ADDRESS "upgradeToAndCall(address,bytes)" $SAFE_IMPL 0x

# 4. Unpause after verification
cast send $PROXY_ADDRESS "unpause()" --private-key $PAUSER_KEY
```

## Common Pitfalls

### ❌ Storage Collision
```solidity
// V1
address public bridge;
address public l1Token;

// V2 - WRONG! Inserted variable causes collision
address public bridge;
address public newVariable; // ❌ Shifts l1Token storage
address public l1Token;
```

### ❌ Type Change
```solidity
// V1
uint256 public someValue;

// V2 - WRONG! Type change corrupts storage
uint128 public someValue; // ❌ Cannot change type
```

### ✅ Correct Upgrade
```solidity
// V1
address public bridge;
address public l1Token;
uint256[48] private __gap;

// V2 - CORRECT
address public bridge;
address public l1Token;
uint256 public newFeature; // ✅ Added at end
uint256[47] private __gap;  // ✅ Gap reduced
```

## Monitoring Post-Upgrade

```bash
# Monitor events
cast logs --address $PROXY_ADDRESS --from-block latest

# Check key metrics
watch -n 10 'cast call $PROXY_ADDRESS "totalSupply()(uint256)"'

# Verify allowlist still works
cast call $PROXY_ADDRESS "isAllowlisted(address)(bool)" $USER_ADDRESS

# Test bridge functionality
# (coordinate with bridge operator)
```

## Resources

- [OpenZeppelin UUPS Docs](https://docs.openzeppelin.com/contracts/4.x/api/proxy#UUPSUpgradeable)
- [Storage Gaps](https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps)
- [Foundry Upgrade Testing](https://book.getfoundry.sh/tutorials/testing-upgradeable-contracts)

## Support

For upgrade assistance:
- Technical questions: tech@cnslabs.com
- Security concerns: security@cnslabs.com
- Mainnet upgrades: require multisig coordination + audit review


# Gas Optimization Guide

## Gas Snapshot Tracking

This project uses Foundry's gas snapshot feature to track gas usage across all test functions and detect regressions.

### Understanding Gas Snapshots

The `.gas-snapshot` file contains a baseline of gas consumption for every test. It's automatically checked in CI to ensure:
- No unexpected gas increases
- Optimizations are tracked and verified
- Gas regressions are caught before deployment

### Working with Gas Snapshots

#### Generate/Update Snapshot
```bash
# Generate or update the gas snapshot
forge snapshot

# Check against existing snapshot (5% tolerance)
forge snapshot --check --tolerance 5

# Show diff against existing snapshot
forge snapshot --diff

# Generate snapshot with custom output
forge snapshot --snap custom-snapshot.txt
```

#### Analyze Gas Usage
```bash
# Run tests with gas report
forge test --gas-report

# Gas report for specific contract
forge test --gas-report --match-contract CNSTokenL2

# Detailed gas report with opcodes
forge test --gas-report -vvvv
```

### CI Integration

The CI pipeline automatically:
1. ✅ Checks gas snapshots with 5% tolerance
2. 📊 Shows diff if changes detected
3. ⬆️ Uploads artifacts for review
4. 📝 Creates summary in PR

### Gas Optimization Checklist

When optimizing for gas:

#### Storage Optimization
- [ ] Pack variables in storage slots (use `forge inspect StorageLayout`)
- [ ] Use `uint256` instead of smaller uints (unless packing)
- [ ] Mark variables as `immutable` or `constant` when possible
- [ ] Use `private` over `public` for variables (saves getter gas)

#### Function Optimization  
- [ ] Use `calldata` instead of `memory` for external function parameters
- [ ] Cache storage variables in memory when used multiple times
- [ ] Use `unchecked` for arithmetic that cannot overflow
- [ ] Prefer custom errors over `require` strings
- [ ] Mark view/pure functions appropriately

#### Pattern Optimization
- [ ] Batch operations where possible (e.g., `setAllowlistBatch`)
- [ ] Use events instead of storage when data doesn't need on-chain access
- [ ] Optimize loop operations (cache length, minimize storage reads)
- [ ] Consider ERC20Permit for gasless approvals

### Gas Benchmarks

Current gas costs (see `.gas-snapshot` for exact values):

**CNSTokenL1**
- Transfer: ~45k gas
- Approve: ~39k gas
- Permit (signature): ~939k gas

**CNSTokenL2**  
- Bridge mint (bypassing allowlist): ~77k gas
- Allowlist transfer: ~156k gas
- Pause/unpause: ~169k gas
- Upgrade: ~2.2M gas

### Monitoring Gas Changes

#### In Pull Requests
1. CI will comment if gas changes exceed 5% tolerance
2. Review the diff in the Actions summary
3. Update snapshot if intentional: `forge snapshot`
4. Commit the updated `.gas-snapshot` file

#### Manual Monitoring
```bash
# Compare branches
git checkout main
forge snapshot --snap main.snapshot

git checkout feature-branch
forge snapshot --snap feature.snapshot

diff main.snapshot feature.snapshot
```

### Gas Optimization Tools

#### Forge Gas Profiler
```bash
# Profile gas usage per opcode
forge test --gas-report -vvvv --match-test testTransfer
```

#### Storage Layout Analysis
```bash
# View storage layout
forge inspect CNSTokenL2 storage-layout

# Check for packing opportunities
forge inspect CNSTokenL2 storage-layout --pretty
```

### Best Practices

1. **Always run `forge snapshot` before committing gas optimizations**
2. **Document significant gas changes in PR descriptions**
3. **Don't sacrifice security for minor gas savings**
4. **Test edge cases after optimizations**
5. **Keep tolerance at 5% to catch regressions**

### Resources

- [Foundry Gas Snapshots](https://book.getfoundry.sh/forge/gas-snapshots)
- [Solidity Gas Optimization](https://github.com/iskdrews/awesome-solidity-gas-optimization)
- [EVM Gas Costs](https://www.evm.codes/)


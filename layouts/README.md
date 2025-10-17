# Storage Layouts

This directory contains baseline storage layout snapshots for upgradeable contracts.

Storage layout validation is **automatically checked in CI** to prevent breaking changes during upgrades.

## Automated CI Validation

On every PR, the CI will:
1. Build the contracts
2. Run OpenZeppelin's storage layout validation: `npx @openzeppelin/upgrades-core validate out/build-info --unsafeAllow missing-initializer`
3. Upload storage layout artifacts for reference
4. Fail if incompatible changes are detected

## Baseline Files

- `CNSTokenL2.json` - Baseline for CNSTokenL2 contract
- `CNSTokenL2V2.json` - Baseline for CNSTokenL2V2 contract

## Updating Baselines

These baseline files are kept for reference and documentation purposes. The actual validation is handled by OpenZeppelin's tool.

If you need to update these reference files:

```bash
# Build contracts
forge build

# Update baseline for a specific contract
cat out/CNSTokenL2.sol/CNSTokenL2.json | jq '.storageLayout.storage' > layouts/CNSTokenL2.json
```

## Manual Validation

You can run the OpenZeppelin validation locally:

```bash
# Build contracts first
forge build

# Run OpenZeppelin validation
npx @openzeppelin/upgrades-core validate out/build-info --unsafeAllow missing-initializer
```

## Understanding Storage Layouts

### Safe Operations ✅
- Add new variables at the END
- Add new functions (don't affect storage)
- Modify function logic
- Use storage gap slots for new variables

### Unsafe Operations ❌
- Reorder existing variables
- Change variable types
- Remove variables
- Insert variables between existing ones

### Storage Gap Usage

Our upgradeable contracts use storage gaps to reserve space for future variables:

```solidity
// In CNSTokenL2
uint256[47] private __gap;
```

**When adding N new storage variables:**
1. Add them at the end of the contract (before the gap)
2. Reduce the gap size by N slots: `uint256[47-N] private __gap;`
3. Update the baseline storage layout

**Example:**
```solidity
// Before (gap of 47)
mapping(address => bool) private _allowlisted;
uint256[47] private __gap;

// After adding 2 new variables (gap of 45)
mapping(address => bool) private _allowlisted;
uint256 private _newVariable1;
address private _newVariable2;
uint256[45] private __gap;  // Reduced by 2
```

## Viewing Storage Layouts

To inspect the current storage layout of a contract:

```bash
# Pretty table format
forge inspect src/CNSTokenL2.sol:CNSTokenL2 storageLayout

# JSON format
forge inspect src/CNSTokenL2.sol:CNSTokenL2 storageLayout --json
```

## See Also

- [UPGRADE_GUIDE.md](../UPGRADE_GUIDE.md) - Comprehensive upgrade checklist
- [SECURITY.md](../SECURITY.md) - Security considerations including storage safety

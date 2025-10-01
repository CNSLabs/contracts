# Security

## Static Analysis

This project uses multiple static analysis tools to ensure code quality and security.

### Automated Tools (CI/CD)

#### Slither
Slither runs automatically on every push and PR. It performs:
- Vulnerability detection
- Code optimization suggestions
- Best practice checks
- Upgrade safety analysis

**Configuration**: See `slither.config.json`

**Manual run**:
```bash
# Install Slither
pip3 install slither-analyzer

# Run analysis
slither . --config-file slither.config.json

# Run with specific detectors
slither . --detect reentrancy-eth,uninitialized-state

# Check upgrade safety (for UUPS contracts)
slither . --detect upgrade-safety
```

### Manual Analysis Tools

#### Aderyn (Rust-based analyzer for Foundry)
```bash
# Install
cargo install aderyn

# Run analysis
aderyn .

# Generate report
aderyn . --output report.md
```

#### Mythril (Symbolic execution)
```bash
# Install
pip3 install mythril

# Analyze specific contract
myth analyze src/CNSTokenL2.sol --solc-json mythril.config.json
```

### Storage Layout Verification

For upgradeable contracts (CNSTokenL2), verify storage layout compatibility:

```bash
# Generate storage layout
forge inspect CNSTokenL2 storage-layout

# Compare layouts between versions
forge inspect CNSTokenL2 storage-layout > layout-v1.json
# After upgrade
forge inspect CNSTokenL2V2 storage-layout > layout-v2.json
diff layout-v1.json layout-v2.json
```

### Security Checklist

Before deploying:

- [ ] Run Slither analysis (`slither .`)
- [ ] Check for upgrade safety (`slither . --detect upgrade-safety`)
- [ ] Review storage layout for upgradeable contracts
- [ ] Run fuzz tests (`forge test --fuzz-runs 10000`)
- [ ] Verify all access controls are properly set
- [ ] Check for reentrancy vulnerabilities
- [ ] Ensure proper event emission
- [ ] Validate initialization logic
- [ ] Test pause/unpause functionality
- [ ] Verify allowlist logic

### Known Issues / Acceptable Findings

Document any known Slither warnings that are acceptable:

1. **Low-level calls in CustomBridgedToken**: Inherited from Linea's audited code
2. **Assembly usage in proxy contracts**: Standard OpenZeppelin patterns

### Reporting Security Issues

Please report security vulnerabilities to: security@cnslabs.com

**Do not** open public issues for security vulnerabilities.


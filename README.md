# CNS Contract Prototyping

Smart contracts and tooling for the CNS token stack across L1 ↔ Linea L2.

## Components

- `CNSTokenL1`: canonical ERC20 on Ethereum L1 with ERC20Permit support.
- `CNSTokenL2`: upgradeable Linea bridged token with pause + transfer allowlist, inheriting Linea's `CustomBridgedToken`.
- Foundry scripts/tests for deployment, upgrade rehearsals, and bridge validation.

## Local Development

```bash
cp env.example .env
forge install
forge build
forge test
```

Key tests:

- `forge test --match-contract CNSTokenL2Test`
- `forge test --match-contract CNSTokenL1Test`
- `forge test --match-contract CNSTokenL2V2Test`

### Local Testing with Anvil

Test deployments locally before deploying to testnets:

```bash
# Terminal 1: Start Anvil
anvil

# Terminal 2: Run automated test suite
./test-local-deployment.sh
```

See [`LOCAL_TESTING_GUIDE.md`](./LOCAL_TESTING_GUIDE.md) for detailed instructions.

## Security

Security documentation and analysis:

- **[Security Audits](security/audits/)** - Audit reports and analysis
- **[Storage Layouts](storage-layouts/)** - Upgrade safety verification  
- **[Security Policies](policies/SECURITY.md)** - Guidelines and procedures
- **[Gas Optimization](policies/GAS_OPTIMIZATION.md)** - Gas optimization guidelines

### Current Security Status: ✅ **PRODUCTION READY**

All critical and high priority security issues have been resolved. See the [latest audit report](security/audits/2025-10-21-ai-analysis.md) for details.

**Report security issues to**: security@cnslabs.com

### Environment Variables

`env.example` lists all variables consumed by deployment scripts. Required placeholders:

- `PRIVATE_KEY`: broadcaster key used by Forge (keep in `.env`, never commit).
- `LINEA_L2_BRIDGE`: network-specific Linea TokenBridge address.
- `CNS_OWNER`: Safe receiving admin, pauser, allowlist, upgrader roles.

Optional RPC overrides (if you want to use custom RPC endpoints):

- `ETH_MAINNET_RPC_URL`, `ETH_SEPOLIA_RPC_URL`: Ethereum L1 RPC endpoints
- `LINEA_MAINNET_RPC_URL`, `LINEA_SEPOLIA_RPC_URL`: Linea L2 RPC endpoints

Load automatically with `direnv` (`use dotenv` already in `.envrc`) or export manually before running scripts.

## Deploying to Testnets

### Separate L1 and L2 Deployments (Recommended)

```bash
# Deploy L1 Token on Sepolia
forge script script/1_DeployCNSTokenL1.s.sol:DeployCNSTokenL1 --rpc-url sepolia --broadcast --verify

# Set CNS_TOKEN_L1 in .env with the deployed address

# Deploy L2 Token on Linea Sepolia
forge script script/2_DeployCNSTokenL2.s.sol:DeployCNSTokenL2 --rpc-url linea_sepolia --broadcast --verify
```
You can optionally override the token name and symbol values by setting the corresponding env variables, or .env file values:
```bash
TOKEN_NAME="Foo Token" TOKEN_SYMBOL=FOO forge script script/1_DeployCNSTokenL1.s.sol:DeployCNSTokenL1 --rpc-url sepolia --broadcast --verify

TOKEN_NAME="Foo Token" TOKEN_SYMBOL=FOO forge script script/2_DeployCNSTokenL2.s.sol:DeployCNSTokenL2 --rpc-url linea_sepolia --broadcast --verify
```

See [`script/README.md`](./script/README.md) for complete deployment workflow.

## Linea Deployment Checklist

- **Pin dependencies**: Vendor `src/linea/BridgedToken.sol` and `CustomBridgedToken.sol` from Linea commit `c7bc6313a6309d31ac532ce0801d1c3ad3426842`. Record this hash in deployment notes.
- **Bridge addresses**: Supply the correct Linea TokenBridge (L2) address through `LINEA_L2_BRIDGE` env var during scripts. Refer to Consensys docs or deployment manifests (e.g., `linea-deployment-manifests`) for network-specific values (Mainnet vs Sepolia).
- **Initializer params**: When calling `CNSTokenL2.initialize`, provide admin Safe, TokenBridge address, linked L1 token, L2 metadata (`name`, `symbol`, `decimals`). Ensure non-zero addresses to satisfy runtime guards.
- **Role separation**:
  - `DEFAULT_ADMIN_ROLE` / `UPGRADER_ROLE`: governance Safe (timelock if possible).
  - `PAUSER_ROLE`: fast-response Safe for incident handling.
  - `ALLOWLIST_ADMIN_ROLE`: operations Safe controlling transfer allowlist.
- **Allowlist defaults**: Implementation auto-allowlists itself, the bridge, and admin. Add additional operational addresses before enabling user transfers.
- **Linking workflow**: Coordinate with Linea bridge operators to link the L1 canonical token to the new L2 implementation. Capture approval transaction hashes for the deployment report.
- **Operational tests**:
  - On Linea Sepolia, simulate deposit (L1 escrow → L2 mint) and withdrawal (L2 burn → L1 release).
  - Verify allowlist enforcement by attempting transfers between non-allowlisted accounts (should revert) and allowlisted accounts (should succeed when unpaused).
  - Exercise pause/unpause and verify the bridge can still mint/burn.
- **Upgrades**: Test a dummy implementation upgrade via Foundry to confirm `_authorizeUpgrade` role gating. Maintain a change log for auditors.
- **Monitoring & runbooks**: Document emergency procedures for pausing, allowlist updates, and upgrade approvals. Consider on-chain monitoring for bridge-exclusive mint/burn events.

## Project Structure

```
src/      # Contracts
script/   # Deployment/ops scripts
test/     # Foundry tests
lib/      # Vendored deps (OZ, Linea, forge-std)
```

## Tooling

- Solidity `0.8.25`, optimizer 200 runs (see `foundry.toml`).
- Upgradeable OZ packages vendored under `lib/openzeppelin-contracts-upgradeable`.
- Format using `forge fmt` before commits.

## License

MIT

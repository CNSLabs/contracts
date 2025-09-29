# CNS Contract Prototyping

Smart contracts and tooling for the CNS token stack across L1 ↔ Linea L2.

## Components

- `CNSTokenL1`: canonical ERC20 on Ethereum L1 with ERC20Permit support.
- `CNSTokenL2`: upgradeable Linea bridged token with pause + transfer allowlist, inheriting Linea's `CustomBridgedToken`.
- `CNSAccessNFT`, `CNSTierProgression`, `CNSTokenSale`: supporting contracts for access control and sale mechanics.
- Foundry scripts/tests for deployment, upgrade rehearsals, and bridge validation.

## Local Development

```bash
forge install
forge build
forge test
```

Key tests:

- `forge test --match-contract CNSTokenL2Test`
- `forge test --match-contract CNSTokenL1Test`

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

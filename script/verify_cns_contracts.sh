#!/usr/bin/env bash
set -euo pipefail

# Verify CNSToken contracts on Sepolia (L1) and Linea Sepolia (L2) using forge
# - L1: Etherscan verifier
# - L2: Blockscout verifier (LineaScan)
#
# Requirements:
# - forge, cast, jq installed and on PATH
# - Environment variable ETHERSCAN_API_KEY set (for L1)
# - By default, reads deployment data from broadcast/multi/DeployCNSContracts.s.sol-latest/run.json
# - You can override addresses/args via env vars below

ROOT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
cd "$ROOT_DIR"

RUN_JSON_DEFAULT="$ROOT_DIR/broadcast/multi/DeployCNSContracts.s.sol-latest/run.json"
RUN_JSON_PATH="${RUN_JSON_PATH:-$RUN_JSON_DEFAULT}"
LINEA_VERIFIER_URL="${LINEA_VERIFIER_URL:-https://api-sepolia.lineascan.build/api}"

if ! command -v forge >/dev/null 2>&1; then
    echo "forge is required but not found on PATH" >&2
    exit 1
fi
if ! command -v cast >/dev/null 2>&1; then
    echo "cast is required but not found on PATH" >&2
    exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required but not found on PATH" >&2
    exit 1
fi

# -----------------------------
# Extract from broadcast JSON
# -----------------------------
if [[ -f "$RUN_JSON_PATH" ]]; then
    # L1 (chain 11155111, Sepolia) CNSTokenL1
    L1_TOKEN_ADDRESS_FROM_JSON=$(jq -r '.deployments[] | select(.chain==11155111) | .transactions[] | select(.contractName=="CNSTokenL1") | .contractAddress' "$RUN_JSON_PATH" 2>/dev/null || echo "")
    L1_ARGS_NAME=$(jq -r '.deployments[] | select(.chain==11155111) | .transactions[] | select(.contractName=="CNSTokenL1") | .arguments[0]' "$RUN_JSON_PATH" 2>/dev/null || echo "")
    L1_ARGS_SYMBOL=$(jq -r '.deployments[] | select(.chain==11155111) | .transactions[] | select(.contractName=="CNSTokenL1") | .arguments[1]' "$RUN_JSON_PATH" 2>/dev/null || echo "")
    L1_ARGS_SUPPLY=$(jq -r '.deployments[] | select(.chain==11155111) | .transactions[] | select(.contractName=="CNSTokenL1") | .arguments[2]' "$RUN_JSON_PATH" 2>/dev/null || echo "")
    L1_ARGS_RECIPIENT=$(jq -r '.deployments[] | select(.chain==11155111) | .transactions[] | select(.contractName=="CNSTokenL1") | .arguments[3]' "$RUN_JSON_PATH" 2>/dev/null || echo "")

    # L2 (chain 59141, Linea Sepolia) CNSTokenL2 implementation and ERC1967Proxy
    L2_IMPL_ADDRESS_FROM_JSON=$(jq -r '.deployments[] | select(.chain==59141) | .transactions[] | select(.contractName=="CNSTokenL2") | .contractAddress' "$RUN_JSON_PATH" 2>/dev/null || echo "")
    L2_PROXY_ADDRESS_FROM_JSON=$(jq -r '.deployments[] | select(.chain==59141) | .transactions[] | select(.contractName=="ERC1967Proxy") | .contractAddress' "$RUN_JSON_PATH" 2>/dev/null || echo "")
    L2_PROXY_IMPL_ARG=$(jq -r '.deployments[] | select(.chain==59141) | .transactions[] | select(.contractName=="ERC1967Proxy") | .arguments[0]' "$RUN_JSON_PATH" 2>/dev/null || echo "")
    L2_PROXY_INIT_CALLDATA_ARG=$(jq -r '.deployments[] | select(.chain==59141) | .transactions[] | select(.contractName=="ERC1967Proxy") | .arguments[1]' "$RUN_JSON_PATH" 2>/dev/null || echo "")
else
    echo "Warning: broadcast run.json not found at $RUN_JSON_PATH; relying on env overrides only." >&2
    L1_TOKEN_ADDRESS_FROM_JSON=""
    L1_ARGS_NAME=""
    L1_ARGS_SYMBOL=""
    L1_ARGS_SUPPLY=""
    L1_ARGS_RECIPIENT=""
    L2_IMPL_ADDRESS_FROM_JSON=""
    L2_PROXY_ADDRESS_FROM_JSON=""
    L2_PROXY_IMPL_ARG=""
    L2_PROXY_INIT_CALLDATA_ARG=""
fi

# -----------------------------
# Allow env overrides
# -----------------------------
L1_TOKEN_ADDRESS="${L1_TOKEN_ADDRESS:-${L1_TOKEN_ADDRESS_FROM_JSON:-}}"
L2_IMPLEMENTATION_ADDRESS="${L2_IMPLEMENTATION_ADDRESS:-${L2_IMPL_ADDRESS_FROM_JSON:-}}"
L2_PROXY_ADDRESS="${L2_PROXY_ADDRESS:-${L2_PROXY_ADDRESS_FROM_JSON:-}}"

# Optional overrides for constructor/initializer data
L1_NAME="${L1_NAME:-${L1_ARGS_NAME:-Canonical CNS Token}}"
L1_SYMBOL="${L1_SYMBOL:-${L1_ARGS_SYMBOL:-CNS}}"
L1_SUPPLY="${L1_SUPPLY:-${L1_ARGS_SUPPLY:-100000000000000000000000000}}"
L1_RECIPIENT="${L1_RECIPIENT:-${L1_ARGS_RECIPIENT:-}}"

L2_PROXY_IMPL="${L2_PROXY_IMPL:-${L2_PROXY_IMPL_ARG:-$L2_IMPLEMENTATION_ADDRESS}}"
L2_INIT_CALLDATA="${L2_INIT_CALLDATA:-${L2_PROXY_INIT_CALLDATA_ARG:-}}"

# -----------------------------
# Sanity checks
# -----------------------------
if [[ -z "${ETHERSCAN_API_KEY:-}" ]]; then
    echo "ETHERSCAN_API_KEY must be set for L1 verification" >&2
    exit 1
fi

if [[ -z "$L1_TOKEN_ADDRESS" ]]; then
    echo "Missing L1 token address. Set L1_TOKEN_ADDRESS or provide a valid RUN_JSON_PATH." >&2
    exit 1
fi
if [[ -z "$L2_IMPLEMENTATION_ADDRESS" ]]; then
    echo "Missing L2 implementation address. Set L2_IMPLEMENTATION_ADDRESS or provide a valid RUN_JSON_PATH." >&2
    exit 1
fi
if [[ -z "$L2_PROXY_ADDRESS" ]]; then
    echo "Missing L2 proxy address. Set L2_PROXY_ADDRESS or provide a valid RUN_JSON_PATH." >&2
    exit 1
fi
if [[ -z "$L1_RECIPIENT" ]]; then
    echo "Missing L1 initialSupplyRecipient. Set L1_RECIPIENT or provide a valid RUN_JSON_PATH." >&2
    exit 1
fi

# Encode constructor args for L1 CNSTokenL1
L1_CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(string,string,uint256,address)" "$L1_NAME" "$L1_SYMBOL" "$L1_SUPPLY" "$L1_RECIPIENT")

# Encode constructor args for ERC1967Proxy(address implementation, bytes data)
if [[ -z "$L2_INIT_CALLDATA" ]]; then
    echo "Missing L2 initializer calldata for proxy. Set L2_INIT_CALLDATA or ensure RUN_JSON_PATH is correct." >&2
    exit 1
fi
L2_PROXY_CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(address,bytes)" "$L2_PROXY_IMPL" "$L2_INIT_CALLDATA")

echo "=== Starting Verification ==="
echo "Repo root: $ROOT_DIR"
echo "Using broadcast file: $RUN_JSON_PATH"

echo
echo "[L1] Verifying CNSTokenL1 at $L1_TOKEN_ADDRESS on Sepolia (Etherscan)"
echo "forge verify-contract $L1_TOKEN_ADDRESS src/CNSTokenL1.sol:CNSTokenL1 --chain sepolia --etherscan-api-key **** --constructor-args $L1_CONSTRUCTOR_ARGS --watch"
forge verify-contract "$L1_TOKEN_ADDRESS" src/CNSTokenL1.sol:CNSTokenL1 \
  --chain sepolia \
  --etherscan-api-key "$ETHERSCAN_API_KEY" \
  --constructor-args "$L1_CONSTRUCTOR_ARGS" \
  --watch

echo
echo "[L2] Verifying CNSTokenL2 implementation at $L2_IMPLEMENTATION_ADDRESS on Linea Sepolia (Blockscout)"
echo "forge verify-contract $L2_IMPLEMENTATION_ADDRESS src/CNSTokenL2.sol:CNSTokenL2 --watch"
forge verify-contract "$L2_IMPLEMENTATION_ADDRESS" src/CNSTokenL2.sol:CNSTokenL2 \
  --chain linea-sepolia \
  --watch
L2_IMPL_STATUS=$?

echo
echo "[L2] Verifying ERC1967Proxy at $L2_PROXY_ADDRESS on Linea Sepolia (Blockscout)"
echo "forge verify-contract $L2_PROXY_ADDRESS lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy --constructor-args $L2_PROXY_CONSTRUCTOR_ARGS --watch"
forge verify-contract "$L2_PROXY_ADDRESS" lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
  --chain linea-sepolia \
  --constructor-args "$L2_PROXY_CONSTRUCTOR_ARGS" \
  --watch
L2_PROXY_STATUS=$?

echo
echo "All verification requests submitted. You can check statuses at:"
echo "- Etherscan (L1 token): https://sepolia.etherscan.io/address/$L1_TOKEN_ADDRESS#code"
echo "- LineaScan (L2 impl): https://sepolia.lineascan.build/address/$L2_IMPLEMENTATION_ADDRESS#code"
echo "- LineaScan (L2 proxy): https://sepolia.lineascan.build/address/$L2_PROXY_ADDRESS#code"



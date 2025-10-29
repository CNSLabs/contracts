#!/usr/bin/env bash
set -euo pipefail

# Validate storage layout compatibility for upgradeable contracts
# This script ensures that storage layouts don't have breaking changes
# that could corrupt state during upgrades.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LAYOUTS_DIR="$ROOT_DIR/storage-layouts"

echo "=== Storage Layout Validation ==="
echo ""

# Ensure layouts directory exists
if [ ! -d "$LAYOUTS_DIR" ]; then
    echo -e "${RED}Error: storage-layouts/ directory not found${NC}"
    exit 1
fi

# Contracts to validate (upgradeable contracts only)
CONTRACTS=("ShoTokenL2" "ShoTokenL2V2")

all_valid=true

for contract in "${CONTRACTS[@]}"; do
    echo "Checking $contract..."
    
    baseline="$LAYOUTS_DIR/${contract}.json"
    current_artifact="$ROOT_DIR/out/${contract}.sol/${contract}.json"
    
    if [ ! -f "$baseline" ]; then
        echo -e "${YELLOW}  ⚠️  No baseline found for $contract (skipping)${NC}"
        continue
    fi
    
    if [ ! -f "$current_artifact" ]; then
        echo -e "${RED}  ❌ Build artifact not found: $current_artifact${NC}"
        all_valid=false
        continue
    fi
    
    # Extract current storage layout
    current_layout=$(jq '.storageLayout.storage' "$current_artifact")
    baseline_layout=$(cat "$baseline")
    
    # Get the number of storage slots in baseline
    baseline_count=$(echo "$baseline_layout" | jq 'length')
    
    # Extract just the slots for comparison (excluding gaps)
    baseline_slots=$(echo "$baseline_layout" | jq -r '.[] | select(.label != "__gap") | "\(.label):\(.slot):\(.offset):\(.type)"' | sort)
    current_slots=$(echo "$current_layout" | jq -r '.[] | select(.label != "__gap") | "\(.label):\(.slot):\(.offset):\(.type)"' | sort)
    
    # Check if any existing slots have changed
    baseline_array=()
    while IFS= read -r line; do
        baseline_array+=("$line")
    done <<< "$baseline_slots"
    
    has_breaking_changes=false
    
    for baseline_slot in "${baseline_array[@]}"; do
        if [ -z "$baseline_slot" ]; then
            continue
        fi
        
        label=$(echo "$baseline_slot" | cut -d: -f1)
        
        # Check if this slot exists in current with same position
        if ! echo "$current_slots" | grep -q "^${baseline_slot}$"; then
            # Check if label exists but with different slot/offset/type
            if echo "$current_slots" | grep -q "^${label}:"; then
                current_slot=$(echo "$current_slots" | grep "^${label}:" || echo "")
                echo -e "${RED}  ❌ BREAKING CHANGE: Storage variable '$label' has changed${NC}"
                echo "     Baseline: $baseline_slot"
                echo "     Current:  $current_slot"
                has_breaking_changes=true
            else
                echo -e "${YELLOW}  ⚠️  Storage variable '$label' was removed (may be intentional)${NC}"
            fi
        fi
    done
    
    if [ "$has_breaking_changes" = true ]; then
        all_valid=false
        echo -e "${RED}  ❌ $contract has BREAKING storage layout changes${NC}"
        echo ""
        echo "  This could corrupt contract state during upgrades!"
        echo "  If this is intentional, update the baseline:"
        echo "    cat out/${contract}.sol/${contract}.json | jq '.storageLayout.storage' > storage-layouts/${contract}.json"
        echo ""
    else
        # Check for new variables (OK as long as they're at the end)
        current_count=$(echo "$current_layout" | jq 'length')
        new_vars=$(echo "$current_layout" | jq -r '.[] | select(.label != "__gap") | .label' | while IFS= read -r var; do
            if ! echo "$baseline_layout" | jq -r '.[] | .label' | grep -q "^${var}$"; then
                echo "$var"
            fi
        done)
        
        if [ -n "$new_vars" ]; then
            echo -e "${GREEN}  ✅ Compatible (new variables added)${NC}"
            echo "     New variables: $(echo "$new_vars" | tr '\n' ',' | sed 's/,$//')"
        else
            echo -e "${GREEN}  ✅ Compatible (no changes)${NC}"
        fi
    fi
    echo ""
done

echo "=== Validation Complete ==="
if [ "$all_valid" = false ]; then
    echo -e "${RED}❌ Storage layout validation FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}✅ All storage layouts are compatible${NC}"
    exit 0
fi


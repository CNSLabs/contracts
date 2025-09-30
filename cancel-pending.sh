#!/bin/bash
# Cancel pending transactions by sending 0-value transactions with same nonces but higher gas

set -e

echo "Canceling pending transaction with nonce 7..."
echo "You will be prompted to enter your private key..."
cast send 0x3b06a5db330e79173068e927A9495C2442e3Fec5 \
  --value 0 \
  --nonce 7 \
  --gas-price 100gwei \
  --rpc-url https://rpc.sepolia.linea.build \
  --interactive

echo ""
echo "Canceling pending transaction with nonce 8..."
echo "You will be prompted to enter your private key again..."
cast send 0x3b06a5db330e79173068e927A9495C2442e3Fec5 \
  --value 0 \
  --nonce 8 \
  --gas-price 100gwei \
  --rpc-url https://rpc.sepolia.linea.build \
  --interactive

echo "Done! Wait 30 seconds then retry deployment."
